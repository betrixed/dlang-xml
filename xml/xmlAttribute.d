module xml.xmlAttribute;
// Attributes compare on the name only

import std.container.array;
import std.array;
import std.typecons, std.traits;
import std.stdint;
import std.algorithm;
import xml.util.buffer;
/// return index into original range
alias Tuple!(bool,"found",intptr_t,"index") BinaryResult;

/// XML type attributes represented as ordered array
template XMLAttribute(T)
{
	alias immutable(T)[] XmlString;
	/// always a pair
	struct XmlAttribute {
	
		XmlString name;
		XmlString value;

		bool opEquals()(auto ref const XmlAttribute s) const { 
			return (this.name == s.name);
		}
		int opCmp(ref const XmlAttribute s) const {
			if (name.length == 0)
			{
				return (s.name.length > 0) ? 1 : 0;
			}
			if (s.name.length == 0)
			{
				return (name.length > 0) ? -1 : 0;
			}
			return typeid(T[]).compare(&name, &s.name);
		}
	}
	struct AttributeMap {
		//alias Buffer!XmlAttribute AttributeBuffer;
		alias XmlAttribute[] AttributeBuffer;
		AttributeBuffer	attr_;

		bool			needSort_;
		
		this(const XmlAttribute[] src, bool needSort = false)
		{
			attr_ ~= src;
			needSort_ = needSort;
		}
		void opAssign(const XmlAttribute attrb)
		{
			attr_ = [attrb];
			needSort_ = false;
		}
		this(const AttributeMap src)
		{
			attr_ ~= src.attr_;
			needSort_ = src.needSort_;
		}

		BinaryResult binarySearch(ref XmlAttribute value)
		{
			intptr_t e = attr_.length;
			if (e > 1)
			{	
				if (needSort_)
					sort();
			}
			else 
				needSort_ = false;

			intptr_t s = 0;
			
			intptr_t i = 0;
			while (s < e) {
				i =  (e + s) / 2;
				auto cmp = attr_[i].opCmp(value);
				if (cmp > 0) 
					e = i;
				else if (cmp < 0) 
					s = i+1;
				else 
					return BinaryResult(true,i);
			}
			return BinaryResult(false,i);
		}

		const(XmlAttribute)[] peek() const 
		{
			static if (isDynamicArray!(AttributeBuffer))
			{
				return attr_;
			}
			else {
				return attr_.peek;
			}
		}
		int opApply(scope int delegate(const XmlString , const XmlString) dg) const
		{
			uint ct = 0;
			auto items = peek();
			for(uintptr_t k = 0; k < attr_.length; k++)
			{
			    const XmlAttribute* r = &items[k];
				auto result = dg(r.name, r.value);
				if (result)
					return result;
			}
			return 0;
		}
		@property void length(uintptr_t val) { attr_.length = val; }
		@property uintptr_t length() const { return attr_.length; }
		@property bool sorted() const { return !needSort_; }

		void sort()
		{
			static if (isDynamicArray!(AttributeBuffer))
			{
				std.algorithm.sort(attr_);
			}
			else {
				XmlAttribute[] temp = (attr_.ptr_)[0..attr_.length_];
				std.algorithm.sort(temp);
			}
			needSort_ = false;
		}

		void pack(uintptr_t pos = 0)
		{
			static if (isDynamicArray!(AttributeBuffer))
			{
				auto slen = attr_.length;
				auto shrink = removeInit!XmlAttribute(attr_,pos);
				if (shrink > 0)
					attr_.length = slen - shrink;
			}
			else {
				attr_.pack(pos);
			}
		}
		void removeName(XmlString name)
		{
			auto attrb = XmlAttribute(name,[]);
			auto ix = binarySearch(attrb);
			if (ix.found)
			{   // replace the element with nothing
				attr_[ix.index] = XmlAttribute.init;
				pack();
				
			}
		}
		void push(XmlString n, XmlString v)
		{
			attr_ ~= XmlAttribute(n,v);
			needSort_ = (attr_.length > 1);
		}
		void push(const XmlAttribute attrb)
		{
			attr_ ~= attrb;
			needSort_ = (attr_.length > 1);
		}
		void insert(ref XmlAttribute attrb)
		{
			if (attr_.length == 0)
			{
				attr_ ~= attrb;
			}
			else {
				auto ix = binarySearch(attrb);
				if (ix.found)
				{
					// replace
					attr_[ix.index] = attrb;
				}
				else {
					// insert by push
					attr_ ~= attrb;
					needSort_ = true;
				}
			}
		}
		/// Potential to invalidate sort order by change of name
		XmlAttribute opIndex(uintptr_t ix)
		{
			return attr_[ix];
		}

		void opIndexAssign(XmlString value, XmlString name)
		{
			auto attrb = XmlAttribute(name,value);
			insert(attrb);
		}
		
		XmlString get( XmlString key, XmlString elseValue)
		{
			auto attrb = XmlAttribute(key,"");
			auto ix = binarySearch(attrb);
			return (ix.found ? attr_[ix.index].value : elseValue);
		}
		XmlString* opIn_r(ref XmlString key)
		{
			auto attrb = XmlAttribute(key,[]);
			auto ix = binarySearch(attrb);
			return (ix.found ? &attr_[ix.index].value : null);
		}

		void reset()
		{
			attr_.length = 0;
			needSort_ = false;
		}
		intptr_t getDuplicateIndex()
		{
			if (needSort_)
				sort();
			auto blen = attr_.length;
			if (blen < 2)
				return -1;
			for(auto ix = 1; ix < blen; ix++)
			{
				if (attr_[ix].name == attr_[ix-1].name)
				{
					return ix;
				}
			}
			return -1;
		}
	}
}

