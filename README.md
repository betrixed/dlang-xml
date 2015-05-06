DLang-XML
=========

This project started out as investigating the D language via writing an XML parser. This included a D1 version, which has been abandoned.

This repository is a revision undertaken to bring this up to date on D version 2.067

The goal is a fully conforming parser, that passes nearly all the standard conformance tests.

There is also a standalone, separate revised version of the std.xml standalone module, renamed as xml.std.xmlSlicer.
On 32-bit runtime addresses some of its GC issues. There was also abuse of exceptions in validation check.
The xmlSlicer is mainly used as performance comparison.

Progress
--------
As this is big refactor, the module names do not match up to earlier versions. Conformance for validation and error detection of xml documents is complete.

Parser
------
The parser and dom are a template of one of the 3 D language character sizes, char, wchar or dchar. Each of these instances can read any kind of xml encoded document file with any kind of BOM mark at the beginning, if this is a valid document and encoding combination. Most often the usage might be of two sorts.  There is either a document to be parsed from the file system, or from a string obtained by some means. If it is already a string there is a possibility of not allocating as much memory if document or information extracted is to be of the same encoding and character size. The D language leads its self open to the possibility of slicing the existing buffer, and returning segments of the origin document as immutable arrays. There are surely some trade-offs. The module xmlLinkDom provides 4 templated functions to parse the document.

import std.variant;
import xml.xmlLinkDom;

First pick the character type for the DOM document.

auto mydoc = new XMLDOM!(char).Document;
// .. set any expectations of document
DOMConfiguration config = doc.getDomConfig();
// .. if namespaces, the DOM is built from ElementNS and AttrNS, and not plain Element and Attribute types
// .. this means there are memory and performance savings if namespace processing is not required. 
// .. namespaces are false by default
config.setParameter("namespace-declarations",Variant(true));

Pick a source with corresponding character type.

try {
    if (filesystem)
    {
      // file may be of any encoding, endian and character type
      parseXmlFile!(char)( mydoc, filePath, true); 
    }
    else {
    // Must specifify character type of myArray (CT)
      parseXml!(char, CT) ( mydoc, myArray, true);
      // alternative to mostly slice up original array if same document character type ..
      // auto mydoc = new XMLDOM!(wchar).Document;
      // parseXmlSlice(wchar)( mydoc, myArray, true)
    }
}
catch(XmlError xe)
{
  // .. check for errors
}
// .. do stuff with the document


### Console applications
Conformance The conformance test suite versions, all XML documents, are found on http://www.w3.org/XML/Test/
The latest test suite is http://www.w3.org/XML/Test/xmlts20130923.tar.gz .
Unpack the latest into the root directory, which should create a directory named xmlconf and use path to xmlconf.xml file as input.
for instance me$ ./conformance64d --input ../../xmlconf/xmlconf.xml

Conformance - Runs all the XML parser conformance tests. There are currently 2,585 of them. Most of them are beyond the capability of the original std.xml, which cannot process DOCTYPE or validate against it.

Speed - Comparison of the xml.std.xmlSlicer and xml.xmlParser execution times averaged on a simple test file.

BigLoad - Comparison test of GC non-collection issues by object instance counting, for a big XML document. With some creative destruction, everything gets a full cleanup.



Contact : michael.rynn.500@gmail.com
