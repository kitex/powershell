from flask import Flask
import requests
import xml.etree.ElementTree as ET
from datetime import date,datetime

base_url = "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/pages/xmlview?data=daily_treasury_yield_curve&field_tdr_date_value="
 # Namespace fix if needed (depends on structure, Treasury uses default XML namespaces sometimes)

def create_app(): 
    app = Flask(__name__)
    return app

app = create_app()

def get_data(year):
    response = requests.get(base_url+str(year))
    response.raise_for_status()  # Raises an HTTPError if the HTTP request returned an unsuccessful status code

    #print(response.content)
    # Step 2: Parse the XML content
    # Extract data records
    data = []
    root = ET.fromstring(response.content)    
    # Namespace fix if needed (depends on structure, Treasury uses default XML namespaces sometimes)
    ns = {'ns': 'http://www.treasury.gov'} if root.tag.startswith('{') else {}

    # Extract data records
    data = []
    for entry in root.findall('.//{*}content/{*}properties'):
        try:
            parsed_date = datetime.strptime(entry.findtext('{*}NEW_DATE'), "%Y-%m-%dT%H:%M:%S").date().isoformat()
        except:
            continue  # skip if date is malformed
        record = {
            'date': parsed_date,
            '1mo': float(entry.findtext('{*}BC_1MONTH')),
            '2mo': float(entry.findtext('{*}BC_2MONTH')),
            '3mo': float(entry.findtext('{*}BC_3MONTH')),
            '6mo': float(entry.findtext('{*}BC_6MONTH')),
            '1yr': float(entry.findtext('{*}BC_1YEAR')),
            '2yr': float(entry.findtext('{*}BC_2YEAR')),
            '3yr': float(entry.findtext('{*}BC_3YEAR')),
            '5yr': float(entry.findtext('{*}BC_5YEAR')),
            '7yr': float(entry.findtext('{*}BC_7YEAR')),
            '10yr': float(entry.findtext('{*}BC_10YEAR')),
            '20yr': float(entry.findtext('{*}BC_20YEAR')),
            '30yr': float(entry.findtext('{*}BC_30YEAR'))
        }
        data.append(record)

    return data

@app.route('/get_yield_curve')
def get_yield_curve():
    # Step 1: Fetch the XML data from the URL 
    data = get_data(year = date.today().year)

    # Print a few records
    for d in data[:10]:
        print(d)

    print(len(data))
    print(data[len(data)-1])
    return data


if __name__ == '__main__':
    app.run(debug=True)
