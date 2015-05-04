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
As this is big refactor, the module names do not match up to earlier versions. Conformance for validation and error detection of xml documents is nearly complete. 3 testcases need fixing.



### Console applications
Conformance The conformance test suite versions, all XML documents, are found on http://www.w3.org/XML/Test/
The latest test suite is http://www.w3.org/XML/Test/xmlts20130923.tar.gz .
Unpack the latest into the root directory, which should create a directory named xmlconf and use path to xmlconf.xml file as input.
for instance me$ ./conformance64d --input ../../xmlconf/xmlconf.xml

Conformance - Runs all the XML parser conformance tests. There are currently 2,585 of them. Most of them are beyond the capability of the original std.xml, which cannot process DOCTYPE or validate against it.

Speed - Comparison of the xml.std.xmlSlicer and xml.xmlParser execution times averaged on a simple test file.

BigLoad - Comparison test of GC non-collection issues by object instance counting, for a big XML document. With some creative destruction, everything gets a full cleanup.



Contact : michael.rynn.500@gmail.com
