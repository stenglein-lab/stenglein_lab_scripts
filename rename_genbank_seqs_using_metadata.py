#!/usr/bin/env python

# This script renames sequences in a genbank format file using 
# metadata contained in the sequence records
# 
# This is a prelude to tree-making, so the tree tips will have
# better labeled tips
# 
# Mark Stenglein 12/5/2025

import sys
import argparse
import re

from Bio import SeqIO

parser = argparse.ArgumentParser(
formatter_class=argparse.RawDescriptionHelpFormatter,
description=
"""
  This script renames sequences in a genbank format file using the sequences' accession and metadata.

  This is designed to create more useful sequence names for use in building phylogenetic trees.
 
  The extent to which this works for individual sequences reflects the quality of that sequence's metadata.

  The new name will consist of:

  [optional_prefix]_[country_if_present]_[host_if_present]_[year_if_present]_accession
""")

parser.add_argument("genbank_file",    help="Input genbank file")
parser.add_argument("-p", "--prefix",  help="Optional prefix text to being each name with")
parser.add_argument("-y", "--year",    help="Add year to name if present in metadata.  Parsed from collection_data metadata field.", action="store_true")
parser.add_argument("-c", "--country", help="Add country to name if present in metadata. Parsed from geo_loc_name or country (preferred) metadata fields.", action="store_true")
parser.add_argument("-o", "--host",    help="Add host organism to name if present in metadata.  Parsed from host metadata field.", action="store_true")

# Parse command-line arguments
args = parser.parse_args()

# a list of country names to look for in geo_loc_name metadata
country_names = [
"Abkhazia",
"Afghanistan",
"Åland Islands",
"Albania",
"Algeria",
"American Samoa",
"Andorra",
"Angola",
"Anguilla",
"Antarctica",
"Antigua & Barbuda",
"Argentina",
"Armenia",
"Artsakh",
"Aruba",
"Australia",
"Austria",
"Azerbaijan",
"Bahamas",
"Bahrain",
"Bangladesh",
"Barbados",
"Belarus",
"Belgium",
"Belize",
"Benin",
"Bermuda",
"Bhutan",
"Bolivia",
"Bosnia & Herzegovina",
"Botswana",
"Bouvet Island",
"Brazil",
"British Indian Ocean Territory",
"British Virgin Islands",
"Brunei",
"Bulgaria",
"Burkina Faso",
"Burundi",
"Cambodia",
"Cameroon",
"Canada",
"Cape Verde",
"Caribbean Netherlands",
"Cayman Islands",
"Central African Republic",
"Chad",
"Chile",
"China",
"Christmas Island",
"Cocos",
"Colombia",
"Comoros",
"Congo",
"Cook Islands",
"Costa Rica",
"Croatia",
"Cuba",
"Curaçao",
"Cyprus",
"Czechia",
"Côte d’Ivoire",
"Denmark",
"Djibouti",
"Dominica",
"Dominican Republic",
"Ecuador",
"Egypt",
"El Salvador",
"Equatorial Guinea",
"Eritrea",
"Estonia",
"Eswatini",
"Ethiopia",
"Falkland Islands",
"Faroe Islands",
"Fiji",
"Finland",
"France",
"French Guiana",
"French Polynesia",
"French Southern Territories",
"Gabon",
"Gambia",
"Georgia",
"Germany",
"Ghana",
"Gibraltar",
"Greece",
"Greenland",
"Grenada",
"Guadeloupe",
"Guam",
"Guatemala",
"Guernsey",
"Guinea",
"Guinea-Bissau",
"Guyana",
"Haiti",
"Heard & McDonald Islands",
"Honduras",
"Hong Kong SAR China",
"Hungary",
"Iceland",
"India",
"Indonesia",
"Iran",
"Iraq",
"Ireland",
"Isle of Man",
"Israel",
"Italy",
"Jamaica",
"Japan",
"Jersey",
"Jordan",
"Kazakhstan",
"Kenya",
"Kiribati",
"Kosovo",
"Kuwait",
"Kyrgyzstan",
"Laos",
"Latvia",
"Lebanon",
"Lesotho",
"Liberia",
"Libya",
"Liechtenstein",
"Lithuania",
"Luxembourg",
"Macao SAR China",
"Madagascar",
"Malawi",
"Malaysia",
"Maldives",
"Mali",
"Malta",
"Marshall Islands",
"Martinique",
"Mauritania",
"Mauritius",
"Mayotte",
"Mexico",
"Micronesia",
"Moldova",
"Monaco",
"Mongolia",
"Montenegro",
"Montserrat",
"Morocco",
"Mozambique",
"Myanmar",
"Namibia",
"Nauru",
"Nepal",
"Netherlands",
"New Caledonia",
"New Zealand",
"Nicaragua",
"Niger",
"Nigeria",
"Niue",
"Norfolk Island",
"North Korea",
"North Macedonia",
"Northern Cyprus",
"Northern Mariana Islands",
"Norway",
"Oman",
"Pakistan",
"Palau",
"Palestinian Territories",
"Panama",
"Papua New Guinea",
"Paraguay",
"Peru",
"Philippines",
"Pitcairn Islands",
"Poland",
"Portugal",
"Puerto Rico",
"Qatar",
"Romania",
"Russia",
"Rwanda",
"Réunion",
"Sahrawi Arab Democratic Republic",
"Samoa",
"San Marino",
"Saudi Arabia",
"Senegal",
"Serbia",
"Seychelles",
"Sierra Leone",
"Singapore",
"Sint Maarten",
"Slovakia",
"Slovenia",
"Solomon Islands",
"Somalia",
"Somaliland",
"South Africa",
"South Georgia & South Sandwich Islands",
"South Korea",
"South Ossetia",
"South Sudan",
"Spain",
"Sri Lanka",
"St. Barthélemy",
"St. Helena",
"St. Kitts & Nevis",
"St. Lucia",
"St. Martin",
"St. Pierre & Miquelon",
"St. Vincent & Grenadines",
"Sudan",
"Suriname",
"Svalbard & Jan Mayen",
"Sweden",
"Switzerland",
"Syria",
"São Tomé & Príncipe",
"Taiwan",
"Tajikistan",
"Tanzania",
"Thailand",
"Timor-Leste",
"Togo",
"Tokelau",
"Tonga",
"Transnistria",
"Trinidad & Tobago",
"Tunisia",
"Turkey",
"Turkmenistan",
"Turks & Caicos Islands",
"Tuvalu",
"U.S. Outlying Islands",
"U.S. Virgin Islands",
"Uganda",
"Ukraine",
"United Arab Emirates",
"United Kingdom",
"United States",
"USA",
"Uruguay",
"Uzbekistan",
"Vanuatu",
"Vatican City",
"Venezuela",
"Vietnam",
"Wallis & Futuna",
"Western Sahara",
"Yemen",
"Zambia",
"Zimbabwe",
]

# a command to get rid of "special" characters in sequence names  
# e.g. replace whitespaces with underscores and delete commas
def cleanup_name(name):
  name = name.replace(" ", "_")
  name = name.replace(",", "")
  name = name.replace(":", "")
  name = name.replace('"', "")
  name = name.replace('(', "")
  name = name.replace(')', "")
  name = name.replace('/', "")
  name = name.replace('.', "")
  return name  


with open(args.genbank_file) as handle:
   
  for record in SeqIO.parse(handle, "genbank"):

    # new name will be:
    # [prefix_]location_date_accession
 
    # assuming accession is the LOCUS field in genbank record
    accession       = record.name
    # we will parse out geography and date from metadata, if it exists
    geo_loc_name    = None
    collection_date = None
    host            = None

    # iterate through sequences in genbank file
    for feature in record.features:

      # iterate through features of each sequence
      # looking for "source" feature: where the sequence came from
      if feature.type == "source":
        
        # iterate through qualifiers in source feature: individual metadata items
        for qualifier_key, qualifier_value in feature.qualifiers.items():
          qk = qualifier_key.replace("/", "").replace("=","")
          
          # look for a strain or isolate info (not currently using)
          # this assumes one value per qualifier
          if qk == "strain":
             strain_isolate = qualifier_value[0]
          if qk == "isolate":
             strain_isolate = qualifier_value[0]

          # look for location metadata
          # use either geo_loc_name or country (preferred) for location
          if qk == "geo_loc_name":
             geo_loc_name = qualifier_value[0]
          if qk == "country":
             geo_loc_name = qualifier_value[0]

          # look for collection_date metadata
          if qk == "collection_date":
             collection_date = qualifier_value[0]

          # look for host metadata
          if qk == "host":
             host = qualifier_value[0]

    # print (geo_loc_name, file=sys.stderr)
    # print (collection_date, file=sys.stderr)

    # build new name from components
    new_name = ""

    # optional prefix passed in via command-line parameter
    if args.prefix:
      new_name = args.prefix + "_"

    # location metadata
    if geo_loc_name:

      # extract just country name from geo_loc_name
      # using array of country names defined below
      country_names_re = r'\b(' + '|'.join(map(re.escape, country_names)) + r')\b'
      country_match    = re.search(country_names_re, geo_loc_name)
      if country_match:
        geo_loc_name = country_match.group(0)

      if args.country:
         new_name = new_name + geo_loc_name + "_"

    # collection date
    if collection_date:
      # extract just year from date
      year_pattern = r"\d{4}"  
      year = re.search(r"\d{4}", collection_date)
      if year:
        collection_date = year.group(0)

      if args.year:
        new_name = new_name + collection_date + "_"

    # host 
    if host:
      if args.host:
         new_name = new_name + host + "_"

    if accession:
      new_name = new_name + accession

    # run through function to remove special characters and spaces
    new_name = cleanup_name(new_name)

    # overwrite existing name with new name
    record.name = new_name

    # output renamed genbank record to stdout
    SeqIO.write(record, sys.stdout, "genbank")





