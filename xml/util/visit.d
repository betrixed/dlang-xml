module xml.util.visit;

/**
Copyright: Michael Rynn 2012.
Authors: Michael Rynn
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

Template delegates to hand on  XML events

---
*/

import xml.util.buffer;
import xml.util.gcstats;
import xml.txml;
import xml.xmlParser;
import xml.util.inputEncode;

import std.variant, std.stdint;

//debug = VERBOSE;

debug(VERBOSE)
{
	import std.stdio;
}

template XMLSAX(T) {
	alias xml.txml.xmlt!T	vtpl;
	alias vtpl.IXmlDocHandler IXmlDocHandler;
	alias vtpl.IXmlErrorHandler IXmlErrorHandler;
	alias vtpl.XmlEvent		    XmlEvent;

	class XmlDelegate(T) {
   

	alias void delegate(XmlEvent s) ParseDg;

	version (GC_STATS)
	{
		import alt.gcstats;
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

	immutable(T)[]					tagkey_;	 // key for tag name, and parent tag of assorted child types
	ParseDg[XmlResult.DOC_END]		callbacks_;  // common Xml events, expensive sized array

	void setInterface(IXmlDocHandler i)
	{
		callbacks_[XmlResult.TAG_START] = &i.startTag;
		callbacks_[XmlResult.TAG_EMPTY] = &i.soloTag;
		callbacks_[XmlResult.TAG_END] = &i.endTag;
		callbacks_[XmlResult.TEXT] = &i.text;
		callbacks_[XmlResult.CDATA] = &i.cdata;
		callbacks_[XmlResult.COMMENT] = &i.comment;
		callbacks_[XmlResult.XML_DEC] = &i.declaration;
		callbacks_[XmlResult.XML_PI] = &i.instruction;
	}

	this()
	{
		version (GC_STATS)
			gcStatsSum.inc();

	}

	this(XmlDelegate!T other)
	{
		tagkey_ = other.tagkey_;
		callbacks_[]  = other.callbacks_[];
		version (GC_STATS)
			gcStatsSum.inc();
	}

	this(string tagName)
	{
		tagkey_ = tagName; // can be null?
		version (GC_STATS)
			gcStatsSum.inc();
	}

version (GC_STATS)
{
	~this()
	{
		gcStatsSum.dec();
	}
}
	void opIndexAssign(ParseDg dg, XmlEvent rtype)
	in {
		assert(rtype < XmlEvent.DOC_END);
	}
	body {
		callbacks_[rtype] = dg;
	}

	ParseDg opIndex(XmlEvent rtype)
	in {
		assert(rtype < XmlEvent.DOC_END);
	}
	body {
		return callbacks_[rtype];
	}

	bool didCall(ref XmlEvent s)
	in {
		assert(s.eventId < XmlResult.DOC_END);
	}
	body {
		auto dg = callbacks_[s.eventId];
		if (dg !is null)
		{
			dg(s);
			return true;
		}
		return false;
	}

}


/**
Yet another version of callbacks for XML.
---
auto tv = new TagVisitor(xmlParser);

auto mytag = new TagBlock("mytag");
mytag[XmlEvent.TAG_START] = (ref XmlReturn ret){

};
mytag[XmlEvent.TAG_SINGLEs] = (ref XmlReturn ret){

};
---

*/

class TagVisitor(T) : xml.txml.xmlt!T.IXmlErrorHandler {
	// Ensure Tag name, and current associated TagBlock are easily obtained after TAG_END.
	alias XmlDelegate!T TagBlock;
	alias XmlDelegate!T.ParseDg	ParseDg;
	alias xml.xmlParser.XmlParser!T XmlParser;
	alias xml.txml.xmlt!T.XmlEvent   XmlEvent;

	alias immutable(T)[] XmlString;
	alias TagBlock[XmlString]	Namespace;


	private static struct ParseLevel
	{
		string					tagName;
		TagBlock				handlers_;
	};
	XmlParser			parser_;

	Buffer!ParseLevel			parseStack_;
	Buffer!Namespace			nsStack_;

	ParseLevel					current_;			// whats around now.
	intptr_t					level_;				// start with just a level counter.
	//KeyValueBlock!(XmlString,TagBlock,true)			tagHandlers_; // namespace of handlers for tagnames

	bool						called_;
	bool						handlersChanged_;  // flag to recheck stack TagBlock
public:
	TagBlock					defaults;
	XmlResult    				tag;
	Namespace					namespace;

	/// Experimental and dangerous for garbage collection. No other references must exist.
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
	/// create, add and return new TagBlock
	TagBlock create(XmlString tag)
	{
		auto result = new TagBlock(tag);
		namespace[tag] = result;

		return result;
	}

	/// convenience for single delegate assignments for a tag string
	/// Not that null tag will not be called, only real tag names are looked up.
	/// Delegate callbacks can be set to null
	void opIndexAssign(ParseDg dg, XmlString tag, XmlEvent rtype)
	{
		auto tb = namespace.get(tag,null);
		if (tb is null)
		{
			tb = create(tag);
			namespace[tag] = tb;
		}
		tb[rtype] = dg;
	}
	/// return value of a named callback
	ParseDg opIndex(XmlString tag, XmlEvent rtype)
	{
		auto tb = namespace.get(tag, null);
		if (tb !is null)
			return tb[rtype];
		return null;
	}
	/// return block of call backs for tag name
	void opIndexAssign(TagBlock tb, XmlString tag)
	{
		if (tb is null)
			namespace.remove(tag);
		else
		{
			namespace[tag] = tb;
		}
	}	/// return block of call backs for tag name
	TagBlock opIndex(XmlString tag)
	{
		return namespace.get(tag, null);
	}
	/// set a block of callbacks for tag name, using the blocks key value.
	void put(TagBlock tb)
	{
		namespace[tb.tagkey_] = tb;
		handlersChanged_ = true;
	}
	/// set a default call back delegate.

	/// remove callbacks for a tag name.
	void remove(string tbName)
	{
		namespace.remove(tbName);
		handlersChanged_ = true;
	}
	/// Help the garbage collector, done with this object

	void pushNamespace(Namespace tns)
	{
		nsStack_.put(namespace);
		namespace = tns;
	}
	void popNamespace()
	{
		if (nsStack_.length > 0)
		{
			namespace = nsStack_.movePopBack();
		}
	}
	void explode()
	{
		delete parser_;
		/*auto r = tagHandlers.takeArray();
		foreach(ref rec ; r)
			delete rec.value;*/
	}

	this()
	{
		parser_ = new DXmlParser!T();
		parser_.errorInterface = this;
		tag = new XmlEvent!T();
		parser_.eventReturn = tag;
		defaults = new TagBlock();
		version(GC_STATS)
			gcStatsSum.inc();
	}
	void setupNormalize(immutable(T)[] xml)
	{
		parser_.setParameter(xmlAttributeNormalize,Variant(true));
		parser_.initSource(xml);
	}
	void setupRaw(immutable(T)[] xml)
	{
		parser_.setParameter(xmlAttributeNormalize,Variant(false));
		parser_.setParameter(xmlCharFilter,Variant(false));
		parser_.initSource(xml);
	}
	void setupNoSlice(S)(immutable(S)[] xml)
	{
		auto sf = new SliceFill!S(xml);
		ulong pos = 0;
		bool getData(ref const(dchar)[] data)
		{
			return sf.fillData(data,pos);
		}
		parser_.setParameter(xmlAttributeNormalize,Variant(true));
		parser_.initSource(&getData);
	}

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}

	void parseDocument(intptr_t relativeDepth = 0)
    {
        auto    endLevel = parser_.tagDepth() + relativeDepth;

        while(true)
        {
			called_ = false;
			parser_.parseOne();

			switch(tag.type)
			{
				case XmlEvent.TAG_START:
					// a new tag.
					parseStack_.put(current_);
					current_.tagName = tag.scratch;
					current_.handlers_ = namespace.get(tag.scratch,null);
					if (current_.handlers_ !is null)
						called_ = current_.handlers_.didCall(tag);
					break;
				case XmlEvent.TAG_SINGLE:
					// no push required, but check after
					auto tb = namespace.get(tag.scratch,null);
					if (tb !is null)
					{
						called_ = tb.didCall(tag);
					}
					break;
				case XmlEvent.TAG_END:
					debug(VERBOSE) writeln("end " , tag.name, " depth ", parser_.tagDepth(), " ~ ", startLevel);
					if (current_.handlers_ !is null)
						called_ = current_.handlers_.didCall(tag);
					current_ = parseStack_.movePopBack();
					if (handlersChanged_)
						current_.handlers_ = namespace.get(current_.tagName,null);
					auto depth = parser_.tagDepth();
					if (depth == endLevel || depth == 0)
						return; // loopbreaker
					break;
				default:
					if (tag.type < XmlEvent.DOC_END)
					{
						if (current_.handlers_ !is null)
							called_ = current_.handlers_.didCall(tag);
					}
					else if (tag.type == XmlEvent.DOC_END) {
						return;
					}
					break;
			}
			if (!called_)
			{
				auto dg = defaults.callbacks_[tag.type];
				if (dg !is null)
					dg(tag);
			}
        }
    }
}

/// works in similar, but not same way, as std.xml
/// only one instance of ElementParser needed per parse.
/// Uses a stack of delegate handlers.
/// Assumes document level
/// The handler set remains in force, (independent of Xml element Depth, until user pops or pushes another.
/// If as usual all elements have different names, these can be set at the same level, if
/// this fits code design.  User looks after delegate assignment and switching.

/// This was to get over the design issue, that the document level is skipped in std.xml
/// Alternatives - use parse.dombuild, util.visit,

import arraydom = xml.xmlArrayDom;

class XmlHandler(T) : XmlErrorImpl!T
{
	alias XmlEvent!T	XmlReturn;
	alias immutable(T)[] XmlString;
	alias arraydom.XMLARRAY!T.Element	Element;
	alias arraydom.XMLARRAY!T.createElement	createElement;

	alias void delegate(XmlReturn r) Handler; // event object
	alias void delegate(in Element) ElementHandler; // end tag constructed element tree
	alias void delegate(XmlHandler) ParserHandler; // event object is property of parser

	class HandlerSet {
		Handler					  onText;
		Handler					  onPI;
		Handler					  onCDATA;
		Handler					  onComment;
		ParserHandler[XmlString]  onStartTag;
		ElementHandler[XmlString] onEndTag; // A start match starts an Element tree
	}
	private {
		XmlString			src_;
		DXmlParser!T		parser_;
		Buffer!HandlerSet	stack_;
		Buffer!Element		elemStack_;
		// track Element parents, because ArrayDom has no parent field
		// working set
		Handler					  onText_;
		Handler					  onPI_;
		Handler					  onCDATA_;
		Handler					  onComment_;
		Handler					  onXmlDec_;

		bool called_;
	}
public:
	ParserHandler[XmlString]  onStartTag;
	ElementHandler[XmlString] onEndTag; // A start match starts an Element tree
	@property {
		void onPI(Handler handler) { onPI_ = handler; }
		void onText(Handler handler) { onText_ = handler; }
		void onCDATA(Handler handler) { onCDATA_ = handler; }
		void onComment(Handler handler) { onComment_ = handler; }
		void onXI(Handler handler) { onXmlDec_ = handler; }
	}

	XmlEvent!T	tag;

	this(XmlString s)
	{
		src_ = s;
		parser_ = new DXmlParser!T();
		parser_.errorInterface = this;
		//parser_.docInterface = this;
		tag = new XmlEvent!T();
		parser_.eventReturn = tag;
		stack_.reserve(10);
	}
	// Save existing handlers on stack, employ a new set
	void pushHandlerSet(HandlerSet hs)
	{
		auto hset = new HandlerSet();
		getHandlers(hset);
		stack_.put(hset);
		setHandlers(hs);
	}

	/// replace existing handlers with set saved on stack. Return popped set, if any
	void popHandlerSet()
	{
		if (stack_.length > 0)
		{
			auto hset = stack_.movePopBack();
			setHandlers(hset);
		}
	}
	/// Get current handlers as a set, leaving values unchanged. Uninitialised AA ambiguity may apply.
	void getHandlers(HandlerSet hset)
	{
		hset.onText = onText_;
		hset.onPI = onPI_;
		hset.onCDATA = onCDATA_;
		hset.onComment = onComment_;
		hset.onStartTag = this.onStartTag;
		hset.onEndTag = this.onEndTag;
	}
	/// Apply set to overwrite existing handlers.
	void setHandlers(HandlerSet hset)
	{
		onText_ = hset.onText;
		onPI_ = hset.onPI;
		onCDATA_ = hset.onCDATA;
		onComment_ = hset.onComment;
		this.onStartTag = hset.onStartTag;
		this.onEndTag = hset.onEndTag;
	}
	void setupRaw()
	{
		parser_.setParameter(xmlCharFilter,Variant(false));
		parser_.setParameter(xmlAttributeNormalize,Variant(false));
		parser_.initSource(src_);
	}
	void setupNormalize()
	{
		parser_.setParameter(xmlAttributeNormalize,Variant(true));
		parser_.initSource(src_);
	}

	/**
	Loop each parse event, until current Element endtag

	*/
	void parseDocument(intptr_t relativeAdjust = 0)
	{
		auto   startLevel = parser_.tagDepth() + relativeAdjust;

		while(true)
		{
			parser_.parseOne();
			called_ = false;
			switch(tag.type)
			{
				case XmlEvent.TAG_START:
					// a new tag.
					if (onStartTag !is null)
					{
						auto callMyStart = onStartTag.get(tag.name,null);
						if (callMyStart !is null)
						{
							callMyStart(this);
						}
					}
					auto parent = (elemStack_.length > 0) ? elemStack_.back() : null;
					if (parent !is null)
					{	// building already
						auto e = createElement(tag);
						parent.appendChild(e);
						parent = e;
					}
					else if ((onEndTag !is null) && (tag.data in onEndTag))
					{
						// start building here
						parent = createElement(tag);
					}
					elemStack_.put(parent); // null or not
					break;
				case XmlEvent.TAG_SINGLE:
					// no push required, but check after
					auto parent = (elemStack_.length > 0) ? elemStack_.back() : null;
					if (parent !is null)
					{	// building already
						auto e = createElement(tag);
						parent.appendChild(e);
					}
					if (onStartTag !is null)
					{
						auto callMyStart = onStartTag.get(tag.name,null);
						if (callMyStart !is null)
						{
							callMyStart(this);
						}
					}
					// solo tag is an start + endTag with no content.
					if (onEndTag !is null)
					{
						auto p = onEndTag.get(tag.name,null);

						if (p !is null)
						{
							if (parent is null)
								// make isolated Element
								parent = createElement(tag);
							p(parent);
						}
					}
					break;
				case XmlEvent.TAG_END:
					if (onEndTag !is null)
					{
						auto p = onEndTag.get(tag.name,null);
						auto e = (elemStack_.length > 0) ? elemStack_.movePopBack() : null;
						if ((p !is null) && ( e !is null))
							p(e);
					}
					debug(VERBOSE)
						writefln("Start level %s, tag = %s %s", startLevel, parser_.tagDepth, tag.name);
					auto depth = parser_.tagDepth();

					if ((startLevel == depth) || (depth == 0))
						return;

					break;
				case XmlEvent.TEXT:
					auto parent = (elemStack_.length > 0) ? elemStack_.back() : null;
					if (parent !is null)
						parent.addText(tag.data);
					if (onText_ !is null)
						onText_(tag);
					break;
				default:

					break;
			}
		}
	}
	void explode()
	{

	}
}
}