/**
Tree of string names, reflect and check on Xml document structure.

Authors: Michael Rynn
Licence: <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
Distributed under the Boost Software License, Version 1.0.

*/
module xml.dom.tagnest;

import std.algorithm;

//version = MapNames; // Use an AA

debug(CheckNest)
{
	import std.stdio;
	static uintptr_t gAllocSaved = 0;
}

class TagNest(T) {
	alias immutable(T)[] XmlString;

	XmlString		tag_;
	void*			info_;

	version(MapNames) {
		XmlString[XmlString] attributeNames_;
		TagNest[XmlString] childTags_;
	}
	else {
		XmlString[]	attributeNames_;
		TagNest[]	childTags_;
	}

	this (XmlString tag, void* data = null)
	{
		tag_ = tag;
		info_ = data;
		debug(CheckNest) 
		{
			writeln("New tag ", tag);
		}
	}
	version(MapNames)
	{
		void addChild(TagNest c)
		{
			childTags_[c.tag_] = c;
		}
		TagNest findChild(const(T)[] s)
		{
			auto p = s in childTags_;
			return (p !is null) ? *p : null;
		}
		void	addAttributeName(XmlString s)
		{
			debug(CheckNest) {
				writeln("New attribute ", s);
			}
			attributeNames_[s] = s;
			//sort(attributeNames_);
		}

		XmlString  findAttributeName(const(T)[] s)
		{
			auto result = s in attributeNames_;
			return (result !is null) ? *result : null;
		}	
	}
	else {
		TagNest findChild(const(T)[] s)
		{
			auto a = 0;
			auto b = childTags_.length;
			while (a < b)
			{
				auto mid = (a + b) / 2;
				auto m = childTags_[mid];
				auto i = typeid(XmlString).compare(&s, &m.tag_);
				if (i > 0)
				{
					b = mid;
				}
				else if (i < 0)
				{
					a = mid + 1;
				}
				else {
					return m;
				}
			}
			return null;
		}
		static bool mycomp(TagNest a, TagNest b)
		{
			return a.tag_ > b.tag_;
		}
		void addChild(TagNest c)
		{
			childTags_ ~= c;
			sort!(mycomp)(childTags_);
		}
		void	addAttributeName(XmlString s)
		{
			debug(CheckNest) {
				writeln("New attribute ", s);
			}
			attributeNames_ ~= s;
			sort(attributeNames_);
		}

		XmlString  findAttributeName(const(T)[] s)
		{
			auto result = find(attributeNames_, s);
			return (result.length > 0) ? result[0] : null;
		}	
	}

	void explode()
	{
		info_ = null;
		version(TagNesting)
		{
			debug(CheckNest) writeln("Saved allocations ", gAllocSaved);
		}
		version(MapNames)
		{
			foreach(c ; childTags_)
				c.explode(del);
		}
		else {
			attributeNames_.length = 0;
			foreach(c ; childTags_)
				c.explode();
			childTags_.length = 0;
		}

	}
}
