DLang-XML
=========

This project started out as investigating the D language via writing an XML parser. This included a D1 version, which has been abandoned.

This repository is a revision undertaken to bring this up to date on D version 2.067 

The goal is a fully conforming parser, that passes nearly all the standard conformance tests. 

There is also a standalone, separate revised version of the std.xml standalone module, which addresses some of its GC issues. There was also abuse of exceptions in validation check.  The modified std.xml is mainly used as performance comparison and is implemented in module xml.std.xmlSlicer


### Console applications

Conformance - Runs all the XML parser conformance tests. There are currently 2,585 of them. Most of them are beyond the capability of the original std.xml, which cannot process DOCTYPE or validate against it.

Speed - Comparison of the xml.std.xmlSlicer and xml.xmlParser execution times averaged on a simple test file.

BigLoad - Comparison tests GC non-collection issues by object instance counting, for a big XML document.

Progress
--------
As this is a reworking, the module names do not match up to earlier versions. Tricky corners in conformance are being worked through, in test order, now up to 98.5% success, or 38 tests fails left to fix

Contact : michael.rynn.500@gmail.com
