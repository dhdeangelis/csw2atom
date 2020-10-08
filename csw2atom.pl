#!/usr/local/bin/perl

###############################################################################
# csw2atom.pl
#
# version 0.2
# 2020-09-30
# 
# Writes ATOM feed from metadata records from a CSW catalogue
# 
# Hernán De Angelis, 2020
#
###############################################################################

# required modules
use warnings;
use strict;
use Encode qw(decode encode);
use utf8;
use LWP::Simple;
use LWP::UserAgent;
use XML::LibXML;
use XML::LibXML::XPathContext;
use HTTP::Request::Common qw(GET);
use POSIX qw(strftime);
use List::Util qw(any uniq uniqstr);

# get date
my $date = strftime "%Y-%m-%d", localtime;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# minimal info for header and entries, set manually

# metadata identifier for ATOM Inspire service
my $feedMetadataUUID = qq(#metadata identifier for ATOM Inspire service#);

# ATOM service output filename
my $fileName = qq(my-ATOM-download-service.xml);

# my ATOM title
my $feedTitle = qq(ATOM feed for datasets XYZ);
# if title contains unusual characters
utf8::encode($feedTitle);

# my ATOM subtitle
my $feedSubTitle = qq(# a suitable subtitle#);
# if title contains unusual characters
utf8::encode($feedSubTitle);

# service metadata link
# OBS! Here it is important to write "&amp;" in place of "&"
my $linkServiceMetadata = qq(https://www.geodata.se/geodataportalen/srv/eng/csw-inspire?request=GetRecordById&amp;service=CSW&amp;version=2.0.2&amp;elementSetName=full&amp;id=).$feedMetadataUUID;

# base, root link for ATOM feed
my $linkATOMbase = qq(https://your-organisations-address/atom/inspire);

# join strings to build lintḱ to service
my $linkServiceFile = $linkATOMbase.'/'.$fileName;

# namespace basename
my $nameSpaceBase = qq(https://yournamespace);

# organisation name
my $orgName = qq(YourOrganization);
# in case organisation name has unusual characters
utf8::encode($orgName);
# organisation e-mail address
my $orgMail = qw(data@yourorganization.com);

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# CSW parameters

# catalogue
my $catalogue = "https://catalogue.yourorganization.com/geonetwork?";

# define desired keyword for harvest
my $mdKwd = "Inspire";

# define elementSetName
my $elementSetName = "full";
		
# define maxRecords
my $maxRecords = 1000;
	
# build basic request
# OBS! Here it is important to write "&" and not "&amp;"
my $request_getrec = qq(request=GetRecords&service=CSW&version=2.0.2&namespace=xmlns(csw=http://www.opengis.net/cat/csw)&resultType=results&outputSchema=csw:IsoRecord&outputFormat=application/xml&maxRecords=$maxRecords&elementSetName=$elementSetName&constraintLanguage=CQL_TEXT&constraint_language_version=1.1.0&typeNames=gmd:MD_Metadata);

if (defined $mdKwd) {
	$mdKwd =~s/\s/%20/;
	my $apx = qq(&constraint=keyword%20EQ%20'$mdKwd');
	$request_getrec = $request_getrec.$apx;
	}
	
# assemble final request
my $request = $catalogue.$request_getrec;
print "GetRecords ... \n";
print $request,"\n";

# post request and get records
getstore($request,"metadata_$date.xml");

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# write ATOM header
open (AF, '>', $fileName);
print AF<<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:georss="http://www.georss.org/georss" xmlns:inspire_dls="http://inspire.ec.europa.eu/schemas/inspire_dls/1.0" xml:lang="sv">
	<!-- Description -->
	<title>$feedTitle</title>
	<subtitle>$feedSubTitle</subtitle>
	<!-- Metadata -->
	<link href="$linkServiceMetadata" rel="describedby" type="application/xml" hreflang="sv"/>
	<!-- This feeds link -->
	<link href="$linkServiceFile" rel="self" type="application/atom+xml" hreflang="sv" title="$feedTitle"/>
	<!-- identifierare -->
	<id>$linkServiceFile</id>
	<!-- Restrictions -->
	<rights>None. All data is made available under a Creative Commons CC0 license.</rights>
	<!-- last updated -->
	<updated>$date</updated>
	<!-- contact for this feed -->
	<author>
		<name>$orgName</name>
		<email>$orgMail</email>
	</author>
	<!-- element -->
EOF
close AF;


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# parse XML metadata records and find 

# define DOM
my $dom = XML::LibXML->load_xml( location => "metadata_$date.xml", no_blanks => 1 );
my $xpc = XML::LibXML::XPathContext->new($dom);
$xpc->registerNs('csw', 'http://www.opengis.net/cat/csw/2.0.2');
$xpc->registerNs('xsi', 'http://www.w3.org/2001/XMLSchema-instance');
$xpc->registerNs('gmd', 'http://www.isotc211.org/2005/gmd');
$xpc->registerNs('srv', 'http://www.isotc211.org/2005/srv');
$xpc->registerNs('gco', 'http://www.isotc211.org/2005/gco');
$xpc->registerNs('xlink', 'http://www.w3.org/1999/xlink');
$xpc->registerNs('gts', 'http://www.isotc211.org/2005/gts');
$xpc->registerNs('gml', 'http://www.opengis.net/gml');
$xpc->registerNs('geonet', 'http://www.fao.org/geonetwork');

my @metadataUUID;
my @dataUUID;

# start loop, iterate over each MD_Metadata element and its children
# my %list;
my $count;
foreach my $metadataElement ($xpc->findnodes('//gmd:MD_Metadata')) {
#     print "$count","\n";

	# find UUID
	my $UUID  = $metadataElement->findvalue('./gmd:fileIdentifier');
	$UUID =~ s/[\v\h\s]//g;

	# find scope: dataset or service
	my $scopeCode = $metadataElement->findvalue('./gmd:dataQualityInfo/gmd:DQ_DataQuality/gmd:scope/gmd:DQ_Scope/gmd:level/gmd:MD_ScopeCode/@codeListValue');

	# find title, different specifications for service or dataset
	my $title;
	$title = $metadataElement->findvalue('./gmd:identificationInfo/gmd:MD_DataIdentification/gmd:citation/gmd:CI_Citation/gmd:title');

	$title =~ s/[\v]//g;
		$title =~ s/^[\s]{1,}//g;
		$title =~ s/[\s]{1,}$//;
		utf8::encode($title);

	# find MD_identifier, different specifications for service or dataset
	my $dataIdentifier;
	$dataIdentifier = $metadataElement->findvalue('./gmd:identificationInfo/gmd:MD_DataIdentification/gmd:citation/gmd:CI_Citation/gmd:identifier/gmd:MD_Identifier');

# 	parse roles if necessary, to change organisation name and adress in different datasets
	foreach my $resource ($metadataElement->findnodes('.//gmd:contact/gmd:CI_ResponsibleParty')) {
# 		my $partyRole = $resource->findvalue('.//gmd:role');
		$orgName = $resource->findvalue('.//gmd:organisationName'); 
		$orgMail = $resource->findvalue('.//gmd:electronicMailAddress');
		utf8::encode($orgName);
		utf8::encode($orgMail);
		}
	
	# output depending on chosen titles

    # for example, using a list with metadata identifiers:
	my @list = qw(UUID1 UUID2 UUID3);
	
	# if any of these is found, then proceed to write an ATOM entry
	if (any {$_ eq $UUID} @list) {
	
        # # # # # # # # # # # # # # # # # # # # # # # # # # 
        # just to print on screen what's going on
		$count++;
		
		print "#$count\n\n";
		print "Titel:\n$title\n\n";
		print "Metadata UUID:\n$UUID\n\n";
		print "Resurs UUID: \n$dataIdentifier\n\n";
		
		# # # # # # # # # # # # # # # # # # # # # # # # # # 
		
	# just in case there are unusual characters
	my $mdlinkstring = qq(https://www.geodata.se/geodataportalen/srv/eng/csw-inspire?request=GetRecordById&amp;service=CSW&amp;version=2.0.2&amp;elementSetName=full&amp;id=).$UUID;
	
	# just in case there are unusual characters
	my $dataFileName = $title;
	utf8::decode($dataFileName);
	
	my $nameSpace;
	
	# this segment specifies if data files need to be renamed differently than the metadata post title
	# repeat if necessary
	if ($UUID eq 'UUID1') {
		$dataFileName = qq(dataset UUID1);
		$nameSpace = 'https://datasetnamespace'
		}
	

		
# write single entry
open (AF, '>>', $fileName);
print AF <<EOF;
<!-- entry -->
<entry xmlns:georss="http://www.georss.org/georss" xml:lang="sv"> 
	<!-- <entry> -->
	<title>$title</title>
	<inspire_dls:spatial_dataset_identifier_code>$dataIdentifier</inspire_dls:spatial_dataset_identifier_code>
	<inspire_dls:spatial_dataset_identifier_namespace>$nameSpace</inspire_dls:spatial_dataset_identifier_namespace>
	<!-- link to metadata -->
	<link href="$mdlinkstring" rel="describedby" type="application/xml" hreflang="sv"/>
	<!-- link to dataset -->
	<link rel="alternate" href="$linkATOMbase/$dataFileName.gml" type="application/atom+xml" hreflang="sv" title="$title"/>
	<!-- coordinate reference system -->
	<category term="http://www.opengis.net/def/crs/EPSG/0/4258" label="EPSG:4258"/>
	<!-- self reference	-->
	<id>$linkServiceFile</id>
	<!-- contact -->
	<author>
		<name>$orgName</name>
		<email>$orgMail</email>
	</author>
	<!-- last updated -->
	<updated>$date</updated>
	<summary type="html"><![CDATA[<div><a href="$linkATOMbase/$dataFileName.gml">Dataset in GML format (EPSG:4258)</a></div>]]></summary>
</entry>
EOF

close AF;
    
    }
    
}

# close ATOM FEED
open (AF, '>>', $fileName);
print AF <<EOF;
</feed>
EOF
close AF;

# delete metadata files
unlink glob qq(metadata_*.xml);
