import boto3
from bs4 import BeautifulSoup
import datetime
import json
import jsonpickle
import requests
from typing import Optional
import urllib.parse


# Various POJO helper classes
class Mention(object):
    def __init__(self, link: str, webmention: str):
        self.link = link
        self.webmention = webmention


class Page(object):
    def __init__(self, url: str, last_modified: int, mentions: dict[str, Mention]):
        self.url = url
        self.last_modified = last_modified
        self.mentions = mentions


class Database(object):
    def __init__(self, pages: dict[str, Page]):
        self.pages = pages


class Operation(object):
    def __init__(self, source: str, target: str, webmention_url: str):
        self.source = source
        self.target = target
        self.webmention_url = webmention_url


class Plan(object):
    def __init__(self, db: Database, additions: list[Operation], removals: list[Operation]):
        self.db = db
        self.additions = additions
        self.removals = removals


# This function reads the webmention.json database file from the S3 bucket
def read_database() -> Database:
    client = boto3.client('s3')
    obj = client.get_object(Bucket='akaritakai-webmention-sender-db', Key='webmention.json')
    data = json.loads(obj['Body'].read().decode('utf-8'))
    return jsonpickle.unpickler.Unpickler().restore(data, classes=Database)


# This function writes the webmention.json database file to the S3 bucket
def write_database(db: Database) -> None:
    client = boto3.client('s3')
    data = jsonpickle.pickler.encode(db)
    client.put_object(Bucket='akaritakai-webmention-sender-db', Key='webmention.json', Body=data)


# This function reads the sitemap.xml file and returns a list of URLs to process
def read_sitemap() -> list[str]:
    r = requests.get("https://akaritakai.net/sitemap.xml")
    xml = r.text
    soup = BeautifulSoup(xml, "html.parser")
    tags = soup.find_all("loc")
    return [tag.text for tag in tags]


# This functions returns the value in the Last-Modified header of a given URL
# The value is returned in seconds since the Unix epoch
def find_last_modified(url) -> int:
    r = requests.get(url)
    header = r.headers['last-modified']
    time = datetime.datetime.strptime(header, '%a, %d %b %Y %X %Z')
    return int(time.timestamp())


# This function finds all the links for a given URL
def find_links(url) -> list[str]:
    r = requests.get(url)
    html = r.text
    soup = BeautifulSoup(html, "html.parser")
    tags = soup.find_all("a")
    links = []
    for tag in tags:
        link = tag["href"]
        link = urllib.parse.urljoin('https://akaritakai.net', link)
        links.append(link)
    return list(set(links))


# This function is a helper function to search the Link header for a webmention URL
def find_webmention_url_in_header(links: dict, base_url: str) -> Optional[str]:
    if 'webmention' in links:
        link = links['webmention']['url']
        link = urllib.parse.urljoin(base_url, link)
        return link


# This function finds the webmention URL for a given URL
def find_webmention_url(url) -> Optional[str]:
    parsed_url = urllib.parse.urlparse(url)
    base_url = f"{parsed_url.scheme}://{parsed_url.netloc}"
    try:
        # Per RFC, try a HEAD request first to prevent wasting the site's bandwidth
        link = find_webmention_url_in_header(requests.head(url).links, base_url)
        if link is not None:
            return link
    except requests.exceptions.RequestException:
        pass
    try:
        # Now we try a GET request
        r = requests.get(url)
        # Per RFC, we check the Link header again first
        link = find_webmention_url_in_header(r.links, base_url)
        if link is not None:
            return link
        # Per RFC, now we find the first <link> or <a> tag in the document with rel="webmention"
        html = r.text
        soup = BeautifulSoup(html, "html.parser")
        tags = soup.find_all(['a', 'link'])
        for tag in tags:
            if 'rel' in tag.attrs and tag['rel'] == 'webmention':
                link = tag['href']
                link = urllib.parse.urljoin(base_url, link)
                return link
        return None
    except requests.exceptions.RequestException as e:
        print(f"Error when reading URL {url}: {e}")
        return None


# This function builds the ideal next version of the webmention.json database file based on current links
def create_intent() -> Database:
    db = Database({})
    for page_url in read_sitemap():
        last_modified = find_last_modified(page_url)
        for link_url in find_links(page_url):
            webmention_url = find_webmention_url(link_url)
            if webmention_url is None:
                continue
            # We want to add this page to our database
            if page_url not in db.pages:
                db.pages[page_url] = Page(page_url, last_modified, {})
            page = db.pages[page_url]
            # We want to add this link to our page
            if link_url not in page.mentions:
                page.mentions[link_url] = Mention(link_url, webmention_url)
    return db


# This process diffs the current database against our ideal database
def create_plan() -> Plan:
    prev_db = read_database()
    next_db = create_intent()

    added = []
    removed = []

    page_urls = set(prev_db.pages.keys()) | set(next_db.pages.keys())
    for page_url in page_urls:
        # Handle pages that were removed
        if page_url not in next_db.pages:
            for mention in prev_db.pages[page_url].mentions.values():
                removed.append(Operation(page_url, mention.link, mention.webmention))
        # Handle pages that were added
        elif page_url not in prev_db.pages:
            for mention in next_db.pages[page_url].mentions.values():
                prev_db.pages[page_url] = Page(page_url, next_db.pages[page_url].last_modified, {})
                added.append(Operation(page_url, mention.link, mention.webmention))
        # Handle pages that may have been modified:
        else:
            prev_page = prev_db.pages[page_url]
            next_page = next_db.pages[page_url]

            # Check the modification date to see if the links might have changed and update DB to latest
            changed = prev_page.last_modified != next_page.last_modified
            prev_page.last_modified = next_page.last_modified
            link_urls = set(prev_page.mentions.keys()) | set(next_page.mentions.keys())
            for link_url in link_urls:
                # Handle links that were removed
                if link_url not in next_page.mentions:
                    webmention_url = prev_page.mentions[link_url].webmention
                    removed.append(Operation(page_url, link_url, webmention_url))
                # Handle links that were added
                elif link_url not in prev_page.mentions:
                    webmention_url = next_page.mentions[link_url].webmention
                    added.append(Operation(page_url, link_url, webmention_url))
                # Since the page updated, we need to reissue webmentions
                elif changed:
                    prev_page.mentions.pop(link_url)
                    webmention_url = next_page.mentions[link_url].webmention
                    added.append(Operation(page_url, link_url, webmention_url))
                # If the webmention link has changed, we probably should notify the new server
                elif prev_page.mentions[link_url].webmention != next_page.mentions[link_url].webmention:
                    prev_page.mentions.pop(link_url)
                    webmention_url = next_page.mentions[link_url].webmention
                    added.append(Operation(page_url, link_url, webmention_url))
    return Plan(prev_db, added, removed)


# This function sends the webmention in question
def send_webmention(op: Operation) -> bool:
    headers = {'Content-Type': 'application/x-www-form-urlencoded'}
    payload = {'source': op.source, 'target': op.target}
    try:
        response = requests.post(op.webmention_url, data=payload, headers=headers)
        print(f"Got response {response.status_code} from {op.webmention_url} for {op.source} -> {op.target}")
        return response.status_code == 201 or response.status_code == 202
    except requests.exceptions.RequestException as e:
        print(f"Error when sending webmention to {op.webmention_url}: {e}")
        return False


# This function performs the plan
def process_plan(plan: Plan) -> Database:
    for operation in plan.removals:
        if send_webmention(operation):
            print(f"Removed {operation.source} -> {operation.target}")
            plan.db.pages[operation.source].mentions.pop(operation.target)
    for operation in plan.additions:
        if send_webmention(operation):
            print(f"Added {operation.source} -> {operation.target}")
            plan.db.pages[operation.source].mentions[operation.target] = Mention(operation.target,
                                                                                 operation.webmention_url)
    return plan.db


def lambda_handler(event, context):
    plan = create_plan()
    db = process_plan(plan)
    write_database(db)
