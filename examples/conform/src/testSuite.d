module testSuite;

import texi.buffer,  texi.read;
import xml.dom.domt,xml.txml;
import xml.xmlError, xml.xmlParser, xml.xmlLinkDom;
import texi.inputEncode;
import texi.inputblock;
import xml.util.jisx0208;
import std.stdint, std.path, std.stdio;
import std.algorithm;


version(GC_STATS)
{
	import texi.gcstats;
}
import std.file, std.conv, std.variant, std.string;
template XMLTESTS(T)
{
	alias xmlt!(T).XmlString  XmlString;
    alias XMLDOM!T.NamedNodeMap NamedNodeMap;
    alias XMLDOM!T.Entity Entity;
    alias XMLDOM!T.EntityReference EntityReference;
    alias XMLDOM!T.DocumentFragment DocumentFragment;
    alias XMLDOM!T.DocumentType DocumentType;
	alias XMLDOM!T.Node			Node;

	alias XMLDOM!(T).Element			Element;
	alias XMLDOM!(T).ChildElementRange	ChildElementRange;
	alias XMLDOM!(T).ChildNodeRange	    ChildNodeRange;

	alias XMLDOM!(T).Document			Document;
	alias XMLDOM!(T).DOMConfiguration	DOMConfiguration;
	alias XMLDOM!(T).DOMVisitor			DOMVisitor;
	alias XMLDOM!(T).printDocument		printDocument;

	class XmlConfTest
	{

		XmlString  id;
		intptr_t order_;
		XmlString  test_type;

		XmlString  entities;
		XmlString  sections;
		XmlString  description;
		string		output;
		string		baseDir;
		string		uri;
		XmlString  namespace;
		string  edition;
		bool    passed = false;
		bool    summary = true;

		void failMessage()
		{
			writefln("Failed catagory %s, input %s", test_type, uri);
			writefln("Path : %s", baseDir);
		}
		override int opCmp(Object obj) const
		{
			auto cobj = cast(XmlConfTest)obj;
			if (cobj is null)
				return -1;
			else
				return cast(int)(this.order_ - cobj.order_);
		}
	}

	class Tests {
		bool summary = true;
		bool validate;
		bool namespaceAware = true;
		bool xmlversion11;
		bool stopOnFail = true;
		XmlString	testName;
		string  testsXmlFile;
		string  baseDir;
		string  workDir;
		XmlConfTest[XmlString] tests;

		static this()
		{
            register_EUC_JP();
		}
		int perform()
		{
			baseDir = dirName(testsXmlFile);
			workDir = getcwd();
			if (!isAbsolute(baseDir))
				baseDir = absolutePath(baseDir,workDir);
			writeln("Test file in ", baseDir);
			if (testsXmlFile !is null)
			{
				if (readTests(testsXmlFile))
				{
					if (testName.length == 0)
					{
						runTests(baseDir, stopOnFail);
					}
					else
					{
						bool found = false;
						auto t = tests.get(testName,null);

						if (t !is null)
						{
							found = true;
							writefln("Test = No. %s : %s ", t.order_,testName);
							getchar(); // wait for setting up break points in debugger
							XmlConfResult rt1 = runTest(t,baseDir,true);
							showResult(rt1);

							XmlConfResult rt0 = runTest(t,baseDir,false);
							showResult(rt0);

							t.passed = rt0.passed && rt1.passed;
							destroy(rt1);
							destroy(rt0);
							if (!summary)
								writeln(t.description);
							if (!t.passed)
							{
								t.failMessage();
							}
						}
						else
						{
							writefln("test id not found %s", testName);
						}
					}
				}
			}
			return 0;
		}
		bool readTests(string path)
		{
			bool result= true;

			string dirName = dirName(path);
			string fileName = baseName(path);
			writeln("Test file  ", fileName, " from ", dirName);

			Document doc = new Document(null,to!XmlString(path)); // path here is just a tag label.

			scope(exit)
			{
				doc.explode();
			}
			auto peh = new ParseErrorHandler();

			auto config = doc.getDomConfig();
			//Variant v = cast(DOMErrorHandler) peh;
			config.setParameter("error-handler",Variant(cast(DOMErrorHandler) peh));
			config.setParameter("namespaces", Variant(false));
			// don't expand entity nodes, store them in the DocType Node
            config.setParameter("entities", Variant(true));

			//if (!std.path.isabs(dirName)) // should work either way
			//	dirName = rel2abs(dirName);
			try
			{
				parseXmlFile(doc,path,true);
			}
			catch(XmlError pe)
			{
				writeln("Error reading test configuration ",pe.toString());
				return false;
			}

			catch(Exception e)
			{
				writeln(e.toString());
				return false;
			}


			intptr_t orderNum = 0;
            DocumentType dtd = doc.getDoctype();
            NamedNodeMap entityMap = dtd.getEntities();

			foreach( Element e; ChildElementRange(doc.getDocumentElement))
			{
				if (e.getNodeName() == "TESTCASES")
                    testCasesElement(entityMap, e,orderNum);
			}

            writeln(orderNum, " total tests");
            return true;
		}

		bool runTests(string baseDir, bool stopfail)
		{
			//writefln("To run %d tests from %s", tests.length, baseDir);


			auto testList = tests.values;
			std.algorithm.sort!"a<b"(testList);

			int passct = 0;
			int notvalpass = 0;
			int isvalpass = 0;
			int runct = 0;


		STUFF_NOW:
			foreach(ix, test ; testList)
			{
				runct++;
				if (!summary)
					writefln("test %s", test.id);

				XmlConfResult rt0 = runTest(test, baseDir, validate);

				if (rt0.passed)
				{
					passct++;
					if (!stopfail && !summary)
					{
						writefln("passed %s", test.id);
					}
				}
				else
				{
					if (!summary || stopfail)
					{
						writefln("Failed test %d", runct);
						showResult(rt0);
						test.failMessage();
					}
					if (stopfail)
						return false;
				}

			}

			double pct(double v, double t)
			{
				return v * 100.0 / t;
			}

			double total = tests.length;

			writefln("%d tests, passed %d (%g%%)",
					 tests.length, passct, pct(passct,total));

			return true;
		}
		/// add a new test to the array using element
		XmlConfTest doTestElement(Element e, string baseDir)
		{
			XmlConfTest test = new XmlConfTest();

			auto ns = e.getAttribute("RECOMMENDATION");
			if ((ns.length > 2) && ns[0..2] == "NS")
			{
				test.namespace = ns[2..$];
			}

			test.id = e.getAttribute("ID");
			test.edition = to!string(e.getAttribute("EDITION"));

			test.test_type = e.getAttribute("TYPE");
			test.entities = e.getAttribute("ENTITIES");
			test.uri = to!string(e.getAttribute("URI"));


			test.sections = e.getAttribute("SECTIONS");
			test.output = to!string(e.getAttribute("OUTPUT"));
			test.baseDir = baseDir;
			test.description = e.getTextContent();

			return  test;

		}

		void testCasesElement(NamedNodeMap entityMap, Element cases, ref intptr_t orderNum)
		{
			// extract base directory, then the test cases
			auto baseDir = cases.getAttribute("xml:base");
			auto slen = baseDir.length;
			if (slen > 0)
			{
				slen--;
				if (baseDir[slen] == '\\' || baseDir[slen] == '/')
					baseDir.length = slen;
			}
            // baseDir is wrong in one instance -"eduni/namespaces/misc/"

            // use parser for EntityRef node instead

			void testElement(Element te)
			{
                auto dir = to!string(baseDir);
                auto t = doTestElement(te,dir);
                if (t !is null)
                {
                    t.order_ = ++orderNum;
                    t.summary = this.summary;
                    tests[t.id] = t;
                }
			}
			void subTestCases(Element sub)
			{
                foreach(Element e; ChildElementRange(sub))
                {
                    auto tag = e.getNodeName();
                    if (tag == "TEST")
                    {
                        testElement(e);
                    }
                }
			}

			foreach(Node n; ChildNodeRange(cases))
			{
                if (n.getNodeType() == NodeType.Entity_Reference_node)
                {
                    auto ename = n.getNodeName();
                    auto enode = entityMap.getNamedItem(ename);
                    auto entity = cast(Entity) enode;
                    if (entity)
                    {
                        // it was the SystemID
                        baseDir = entity.getNodeValue();
                        // strip off the file name
                        baseDir = dirName(baseDir);

                        // get its DOM Tree fragment
                        DocumentFragment df = entity.getFragment();
                        foreach(Element e; ChildElementRange(df))
                        {
                            auto tag = e.getNodeName();
                            if (tag == "TESTCASES")
                            {
                                subTestCases(e);
                            }
                            else if (tag == "TEST")
                            {
                                testElement(e);
                            }
                        }

                    }

                }
			}
		}
	}




	// collect all the information and put it in a string

	class ParseErrorHandler : DOMErrorHandler
	{
		uint	  domErrorLevel;
		string	  msg;
		version(GC_STATS)
		{
			mixin GC_statistics;
			static this()
			{
				setStatsId(typeid(typeof(this)).toString());
			}
		}
		this()
		{
			version(GC_STATS)
				gcStatsSum.inc();
		}
		~this()
		{
			version(GC_STATS)
				gcStatsSum.dec();
		}

		override bool handleError(DOMError error)
		{
			string[]  errors;
			auto checkLevel = error.getSeverity();
			if (checkLevel > domErrorLevel)
				domErrorLevel = checkLevel;

			msg = error.getMessage();

			if (msg !is null)
			{
				errors ~= to!string(msg);
			}

			DOMLocator loc = error.getLocation();
			if (loc !is null)
			{
				errors ~= format("filepos %d,  line %d, col %d", loc.getByteOffset(), loc.getLineNumber(), loc.getColumnNumber());
			}
			auto ex = error.getRelatedException();
			if (ex !is null)
			{
				auto xe = cast(XmlError) ex;
				if (xe !is null)
					errors ~= xe.errorList;
			}

			if (errors.length == 0)
			{
				errors ~= "unknown error";

			}

			msg = std.string.join(errors,"\n");

			return false;
		}

		override string toString() const
		{
			return msg;
		}
	}

	/**
	* Conformance test result
	**/
	class XmlConfResult : DOMErrorHandler
	{
		XmlConfTest test;
		bool      validate;
		bool      passed;
		bool      outputMatch;
		bool      hadError;
		uint	  domErrorLevel;

		string    thrownException;
		string    output;
		string[]  errors;

		version(GC_STATS)
		{
			mixin GC_statistics;
			static this()
			{
				setStatsId(typeid(typeof(this)).toString());
			}
		}
		this()
		{
		version(GC_STATS)
			gcStatsSum.inc();
		}
		~this()
		{
			version(GC_STATS)
				gcStatsSum.dec();
		}
		override bool handleError(DOMError error)
		{
			bool result = false;

			hadError = true;
			auto checkLevel = error.getSeverity();
			if (checkLevel > domErrorLevel)
				domErrorLevel = checkLevel;

			auto msg = error.getMessage();

			if (msg !is null)
			{
				errors ~= to!(string)(msg);
			}

			DOMLocator loc = error.getLocation();
			if (loc !is null)
			{
				errors ~= format("filepos %d,  line %d, col %d", loc.getByteOffset(), loc.getLineNumber(), loc.getColumnNumber());
			}

			if (errors.length == 0)
			{
				errors ~= "unknown error";

			}
			return result;
		}
	}




	/**
	* Read the test specifications into the array of XmlConfTest from the xml file.
	**/



	/**
	* Run a single test
	*/

	XmlConfResult runTest(XmlConfTest t, string rootDir, bool validate)
	{

		uint[] editions = null;

		uint maxEdition()
		{
			if (editions is null)
				return 5;
			uint max = 0;
			foreach(edval ; editions)
				if (edval > max)
					max = edval;
			return max;
		}

		bool hasEdition(uint ednum)
		{
			if (editions is null)
				return true;

			foreach(edval ; editions)
			{
				if (ednum == edval)
					return true;
			}
			return false;
		}

		if (t.edition.length > 0)
		{
			string[] values = split(t.edition);
			foreach(v ; values)
			{
				editions ~= to!uint(v);
			}
		}
		XmlConfResult result = new XmlConfResult();
		result.test = t;
		result.validate = validate;

		Document doc; // keep for big exceptions
		scope(exit)
		{
			doc.explode();
		}

		try
		{

			if (t.uri.length == 0)
				writeln("t.uri ", t.uri);
			if (t.uri.endsWith("pr-xml-euc-jp.xml") || t.uri.endsWith("weekly-euc-jp.xml"))
			{
				auto c8p = getRecodeCharFn("euc-jp");
				if (c8p !is null)
				{
					t.test_type = "valid";
				}
			}
			string sourceXml = std.path.buildPath(rootDir, t.baseDir, t.uri);
			string baseDir = dirName(sourceXml);

			string[] plist = [baseDir];

			doc = new Document(null,to!XmlString(sourceXml));
			DOMConfiguration config = doc.getDomConfig();
			// The cast is essential, polymorphism fails for Variant.get!
			auto vbal = (t.namespace.length > 0);

			config.setParameter(xmlNamespaces,Variant(vbal) );
			config.setParameter("namespace-declarations",Variant(vbal));
			config.setParameter("error-handler",Variant( cast(DOMErrorHandler) result) );
			config.setParameter("edition", Variant( maxEdition() ) );
			config.setParameter("canonical-form",Variant(true)); // flag for output hint?
			//config.setParameter("entities",Variant(false)); // flag for output hint?
			if (t.summary)
			{
				writeln(t.id);
			}
			parseXmlFile(doc, sourceXml, validate);
			// or parseXmlSliceFile
		}


		catch(XmlError x)
		{
			// bombed
			if (!t.summary)
			{
				if (result.errors.length > 0)
				{
					writefln("DOM Error Handler exception");
					foreach(s ; result.errors)
						writeln(s);

				}
				else
				{
					writefln("General exception %s", x.toString());
				}
			}
			else {
				//auto elist = x.errorList();
				writeln(x.msg);
			}
			destroy(x);
		}

		catch(Exception ex)
		{
			// anything unexpected.
			if (!t.summary)
				writefln("Non parse exception %s", ex.toString());
			else
				writeln("General Exception", ex.msg);
			result.domErrorLevel = DOMError.SEVERITY_FATAL_ERROR;
			result.hadError = true;
		}

		// did we get an error
		if (t.test_type == "not-wf")
		{
			result.passed = (result.domErrorLevel == DOMError.SEVERITY_FATAL_ERROR);
		}
		else if (t.test_type == "error")
		{
			result.passed = (result.domErrorLevel == cast(uint)  DOMError.SEVERITY_ERROR);
		}
		else if (t.test_type == "invalid")
		{
			if (validate)
				result.passed = (result.domErrorLevel == cast(uint) DOMError.SEVERITY_WARNING);
			else
				result.passed = (result.domErrorLevel == cast(uint) DOMError.NO_ERROR);
		}
		else if (t.test_type == "valid")
		{
			result.passed = !result.hadError;
		}

		if ((t.output.length > 0) && (result.domErrorLevel <= DOMError.SEVERITY_WARNING))
		{
			// output the document canonically, compare with Conformance suite output document.
			Buffer!char app;

			void output(in T[] s)
			{
				app.put(s);
			}
			printDocument(doc, &output, 0);

			char[] checkend = app.data;
			if (checkend.length > 0 && checkend[$-1] == '\n')
				app.length = checkend.length - 1;
			string sdoc = app.idup;

			/// now compare to output
			string bestPath = buildPath(rootDir,t.baseDir, t.output);
			string cmpResult =  cast(string)std.file.read(bestPath);
			bool matches = (cmp(sdoc,cmpResult) == 0);
			if (!matches)
			{
				// output the difference between the 2 versions
				auto minsize = sdoc.length;
				if (minsize > cmpResult.length)
					minsize = cmpResult.length;

				size_t lineNo = 0;
				size_t linePos = 0;
				for(size_t kix = 0; kix < minsize; kix++)
				{
					if (sdoc[kix] != cmpResult[kix])
					{
						writeln("Difference at character ", kix, " : Line ", lineNo, " pos ", linePos);
						writefln("got %s, expected %s  (%x, %x)", sdoc[kix], cmpResult[kix], sdoc[kix], cmpResult[kix]);
						break;
					}
					if (sdoc[kix] == '\n')
					{
						lineNo++;
						linePos = 0;
					}
					else
					{
						linePos++;
					}
				}
				if (minsize < sdoc.length)
				{
					for(size_t kix = minsize; kix < sdoc.length; kix++)
						writefln("extra 0x%x", sdoc[kix]);
					writeln(sdoc[minsize .. sdoc.length]);


				}
				writeln(cmpResult);
				writeln(sdoc);
				result.passed = false;

			}
		}

		return result;
	}

	void showResult(XmlConfResult rt)
	{
		void showValidate()
		{
			if (rt.hadError)
				writefln("validate %d error-level %d id %s", rt.passed, rt.validate, rt.test.id);
			else
				writefln("validate %d id %s", rt.validate,rt.test.id);
		}

		if (rt.passed)
		{
			write("passed: ");
			showValidate();
		}
		else
		{
			write("failed: ");
			showValidate();
			foreach(er ; rt.errors)
			{
				writefln("Error: %s",er);
			}
		}
	}
	/**
	* Run multiple tests.
	**/
}
