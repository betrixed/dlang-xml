module xml.sax;

/**
Copyright: Michael Rynn 2012.
Authors: Michael Rynn
License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.

SAX xml event Template delegates to get call backs on Xml Parse events

---
*/

import xml.util.buffer;
import xml.util.gcstats;
import xml.txml;
import xml.parser;
import xml.input;
import xml.util.inputEncode;
import xml.parser;


import std.variant, std.stdint;

//debug = VERBOSE;

debug(VERBOSE)
{
	import std.stdio;
}


class Sax(T) {
    // experience tells that GC should not be always taken for granted
    version (GC_STATS)
    {
        import xml.util.gcstats;
        mixin GC_statistics;
        static this()
        {
            setStatsId(typeid(typeof(this)).toString());
        }
    }
    // look me up, key for tag name, and parent tag of assorted child types
    immutable(T)[]				tagkey_;	 //
    // array for lookup of common SAX events, an array block. Alternative is an AA, which will test to use even more

    alias void delegate(const XmlEvent!T s)  SaxDg;
    SaxDg[SAX.DOC_END]			callbacks_;


    ~this()
    {
        callbacks_[0..SAX.DOC_END] = null;
        tagkey_ = [];
        version (GC_STATS)
                gcStatsSum.dec();
    }
    this()
    {
        callbacks_[0..SAX.DOC_END] = null;
        version (GC_STATS)
            gcStatsSum.inc();

    }

    this(Sax other)
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


    void setInterface(IBuildDom!T idiom) {
        callbacks_[SAX.TAG_START] = &idiom.startTag;
        callbacks_[SAX.TAG_SINGLE] = &idiom.soloTag;
        callbacks_[SAX.TAG_END] = &idiom.endTag;
        callbacks_[SAX.TEXT] = &idiom.text;
        callbacks_[SAX.CDATA] = &idiom.cdata;
        callbacks_[SAX.COMMENT] = &idiom.comment;
        callbacks_[SAX.XML_PI] = &idiom.instruction;
        callbacks_[SAX.XML_DEC] = &idiom.declaration;
    }
    void opIndexAssign(SaxDg dg, SAX rtype)
    in {
        assert(rtype < SAX.DOC_END);
    }
    body {
        callbacks_[rtype] = dg;
    }

    SaxDg opIndex(SAX rtype)
    in {
        assert(rtype < SAX.DOC_END);
    }
    body {
        return callbacks_[rtype];
    }

    bool didCall(const XmlEvent!T s)
    in {
        assert(s.eventId < SAX.DOC_END);
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

class TagSpace(T)
{
    alias immutable(T)[] XmlString;
    alias Sax!T          Sxc;

	Sxc[XmlString]	tags;

	alias void delegate(const XmlEvent!T evt) SaxDg;

	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}

		this()
		{
			gcStatsSum.inc();
		}

	}

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
		foreach(k ; tags.byKey())
		{
			auto r = tags[k];
			tags.remove(k);
			destroy(r);
		}
		tags = null;
	}
	Sxc create(XmlString tag)
	{
		auto result = new Sxc(tag);
		tags[tag] = result;
		return result;
	}
	Sxc opIndex(XmlString tag)
	{
		return tags.get(tag, null);
	}
	SaxDg opIndex(XmlString tag, SAX rtype)
	{
		auto tb = tags.get(tag, null);
		if (tb !is null)
			return tb[rtype];
		return null;
	}
	// puts into current namespace
	void put(Sxc tb)
	{
		tags[tb.tagkey_] = tb;
	}

	void remove(XmlString tag)
	{
		tags.remove(tag);
	}
	void opIndexAssign(Sxc tb, XmlString tag)
	{
		if (tb is null)
			tags.remove(tag);
		else
		{
			tags[tag] = tb;
		}
	}	/// return block of call backs for tag name
	void opIndexAssign(SaxDg dg, XmlString tag, SAX rtype)
	{
		auto tb = tags.get(tag,null);
		if (tb is null)
		{
			tb = create(tag);
			tags[tag] = tb;
		}
		tb[rtype] = dg;
	}
}

class SaxParser(T) {
private:
    alias Sax!T Sxc;

	static struct ParseLevel
	{
		string					tagName;
		Sxc					    handlers_;
	};
	XmlParser!T					parser_;

	Buffer!ParseLevel			parseStack_;
	Buffer!(TagSpace!T)				nsStack_;

	ParseLevel					current_;			// whats around now.
	intptr_t					level_;				// start with just a level counter.
	//KeyValueBlock!(XmlString,TagBlock,true)			tagHandlers_; // namespace of handlers for tagnames

	bool						called_;
	bool						handlersChanged_;  // flag to recheck stack TagBlock
public:
	Sxc							defaults;
	TagSpace!T					namespace;

	/// Experimental and dangerous for garbage collection. No other references must exist.
	version (GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

	/// Help the garbage collector, done with this object

	void pushNamespace(TagSpace!T tns)
	{
		nsStack_.put(namespace);
		namespace = tns;
		if (namespace !is null) {
            current_.handlers_ = namespace[current_.tagName];
		}
	}
	void popNamespace()
	{
		if (nsStack_.length > 0)
		{
			namespace = nsStack_.movePopBack();
            if (namespace !is null) {
                current_.handlers_ = namespace[current_.tagName];
            }
		}
	}

	this()
	{
		parser_ = new XmlParser!T();
        parser_.setEventDg(&saxEvent);

		defaults = new Sxc();
		//namespace = new TagSpace(); // namespace creation and destruction responsibility of user

		version(GC_STATS)
			gcStatsSum.inc();
	}

	bool saxEvent(XmlEvent!T tag)
	{
        return true;
	}
	void isHtml(bool val)
	{
		parser_.isHtml(val);
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

	void setupFile(string filePath) {
        parser_.fileSource(filePath);
	}
	void setupNoSlice(S)(immutable(S)[] xml)
	{
		auto sf = new SliceBuffer!S(xml);
		ulong pos = 0;
		parser_.setParameter(xmlAttributeNormalize,Variant(true));
		parser_.fillSource(sf);
	}

	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
		// take what is official
		destroy(parseStack_);
		destroy(nsStack_);
		parser_.explode();

		destroy(defaults);
	}

	void parseDocument(intptr_t relativeDepth = 0)
    {
        auto    endLevel = parser_.tagDepth() + relativeDepth;
		if (namespace is null)
			throw new Exception("namespace property needs to be set in SaxParser");
        auto    tag = parser_.results();

        while(true)
        {
			called_ = false;
			parser_.parseOne();
            switch(tag.eventId)
            {
                case SAX.TAG_START:
                    // a new tag.
                    parseStack_.put(current_);
                    current_.tagName = tag.data;
                    current_.handlers_ = namespace[tag.data];
                    if (current_.handlers_ !is null)
                        called_ = current_.handlers_.didCall(tag);
                    break;
                case SAX.TAG_SINGLE:
                    // no push required, but check after
                    auto tb = namespace[tag.data];
                    if (tb !is null)
                    {
                        called_ = tb.didCall(tag);
                    }
                    break;
                case SAX.TAG_END:
                    debug(VERBOSE) writeln("end " , tag.name, " depth ", parser_.tagDepth(), " ~ ", startLevel);
                    if (current_.handlers_ !is null)
                        called_ = current_.handlers_.didCall(tag);
                    current_ = parseStack_.movePopBack();
                    if (handlersChanged_)
                        current_.handlers_ = namespace[current_.tagName];
                    auto depth = parser_.tagDepth();
                    if (depth == endLevel || depth == 0)
                        return; // loopbreaker
                    break;
                default:
                    if (tag.eventId < SAX.DOC_END)
                    {
                        if (current_.handlers_ !is null)
                            called_ = current_.handlers_.didCall(tag);
                    }
                    else if (tag.eventId == SAX.DOC_END) {
                        return;
                    }
                    break;
            }
            if (!called_)
            {
                auto dg = defaults.callbacks_[tag.eventId];
                if (dg !is null)
                    dg(tag);
            }

        }
    }
}

