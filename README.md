DLang-XML
=========

Validating XML Parser.  Tested against XML Conformance Test Suite.


Also able to parse HTML.


==Release Version 1.0 

Parser has two modes of collecting the parse information. 

Inputs flexible 
	-- files (of various byte-orders, 8 / 16 bit character types.
	-- slices (arrays of characters).
	

Parser can call an event delegate with class XmlEvent(T)  (All classes templates tested with char and wchar)
Or can call method parseOne(), in a loop and access the internal XmlEvent(T) class for parsed data.

Examples of building a DOM -  full implementation with DTD, validation and entity processing.
Simple DOM using D class and array.

SAX event processing with selective delegates for element names and event types.

Release 1.0 of this is ready for use.  

The documentation isn't, but see examples.

html -  	parse a HTML document, using isHTML setup and SAX events.
extract 	more SAX extraction.
conformance	Run the entire 2500+ suite of test examples, throw errors where appropriate.
speed		Timed for xml data extraction against the std.xml


Sax - style interface & simple dom.

Challenges overcome to bring about this version 
	- time and persistance.
	- tracking every File object opened to make sure it gets closed, no matter what exception thrown, in order not to run out of system file handles.


