module xml.dom.dtdt;
/**
These data structures are seperate from other parts of regular DOM
*/
import xml.xmlError;
import xml.txml;
import std.stdint, std.conv, std.array;
import std.ascii;
import std.string;

version(GC_STATS)
	import texi.gcstats;

enum ChildSelect
{
	sl_one,
	sl_choice,
	sl_sequence
}

/// Used to mark ELEMENT declaration lists and element names
enum ChildOccurs
{
	oc_not_set = 0,
	oc_allow_zero = 1,
	oc_one = 2,
	oc_zeroOne = 3,
	oc_allow_many = 4, //
	oc_oneMany = 6, // !zero, + one + many
	oc_zeroMany = 7 // no restriction zero + one + many
}

template XMLDTD(T)
{
	static if (is(T==char))
		alias std.conv.text concats;
	else static if (is(T==wchar))
		alias std.conv.wtext concats;
	else
		alias std.conv.dtext concats;



	alias   immutable(T)[]	XmlString;
    alias   T[]	XmlBuffer;
	//alias	ixml.XmlErrorLevel	XmlErrorLevel;


	struct ExternalID
	{
		XmlString publicId_;
		XmlString systemId_;
	}

	class EntityData
	{
		enum
		{
			Unknown, Found, Expanded, Failed
		}
		int				status_;				// unknown, found, expanded or failed
		XmlString		name_;				// key for AA lookup
		XmlString		value_;				// processed value
		ExternalID		src_;				// public and system id
		EntityType		etype_;				// Parameter, General or Notation?
		RefTagType		reftype_;			// SYSTEM or what?

		bool			isInternal_;	// This was defined in the internal subset of DTD

		XmlString			encoding_;		// original encoding?
		XmlString			version_;	    // xml version ?
		XmlString			ndataref_;		// name of notation data, if any

		//Notation		ndata_;         // if we are a notation, here is whatever it is
		string			baseDir_;		// if was found, where was it?
		EntityData		context_;		// if the entity was declared in another entity
		version(GC_STATS)
		{
			mixin GC_statistics;
			static this()
			{
				setStatsId(typeid(typeof(this)).toString());
			}
		}

		~this()
		{
			version(GC_STATS)
				gcStatsSum.dec();

		}
		this(XmlString id, EntityType et)
		{
			name_ = id;
			etype_ = et;
			status_ = EntityData.Unknown;
			version(GC_STATS)
				gcStatsSum.inc();
		}

		@property void value(const(T)[] s)
		{
			value_ = to!(XmlString)(s);
		}
		@property XmlString value()
		{
			return value_;
		}
	}

	class ExternalDTD
	{
		ExternalID src_;
		bool	   resolved_;

		this(ref ExternalID eid)
		{
			src_ = eid;
		}
	}

	alias  EntityData[XmlString]	EntityDataMap;
	alias  XmlString[XmlString]		XmlStringMap;

	class DocTypeData
	{
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

		private void voidMap(EntityDataMap emap)
		{
			if (emap.length==0)
				return;
			auto kall = emap.keys();
			foreach(k ; kall)
			{
				emap.remove(k);
			}
		}

		void explode()
		{
			voidMap(paramEntityMap);
			voidMap(generalEntityMap);
			voidMap(notationMap);

			destroy(this);

		}

		XmlString			id_;
		ExternalID			src_;
		//bool				resolved_;
		bool				isInternal_;
		bool				undeclaredInvalid_;	// undeclared entity references are invalid instead of not-wf? Errata 3e E13
		//DocumentType	docTypeNode_; // DOM interface

		EntityDataMap		paramEntityMap;
		EntityDataMap 		generalEntityMap;
		EntityDataMap		notationMap;

		ElementDef[XmlString]		elementDefMap;
		AttributeList[XmlString]	attributeListMap;

		XmlStringMap				elementIDMap;

		EntityData getEntity(const(T)[] name, bool isPE = false)
		{
			auto pdef = isPE ? name in paramEntityMap : name in generalEntityMap;
			return (pdef is null) ? null : *pdef;
		}
	}

	class ElementDef
	{
		XmlString id;

		AttributeList   attrList;
		//string   desc_;
		bool    hasPCData;
		bool    hasElements;
		bool    hasAny;
		bool    isInternal;

		FelEntry[]				flatList;
		ChildElemList			childList; // this may be chucked away


		this(XmlString name)//, string desc
		{
			id = name;
			//desc_ = desc;
		}

		 final bool isPCDataOnly() @property const
		 {
			 return (!hasElements && hasPCData);
		 }

		 final bool isEmpty() @property const
		 {
			 return (!hasElements && !hasPCData);
		 }

		 // this effectively simplifies some kinds of expressions
		 package void appendFlatList(ChildElemList elist)
		 {
			 if (elist.children.length > 0)
			 {
				 if (elist.children.length == 1)
				 {
					 // single list or single item
					 ChildId ch = elist.children[0];
					 if (ch.id !is null)
					 {
						 // fix ups.

						 elist.select = ChildSelect.sl_one; // in case reduced by removal #PCDATA choice

						 if ((ch.occurs==ChildOccurs.oc_one) && (elist.occurs != ChildOccurs.oc_one))
						 {
							 // swap the occurs from outside the list to inside
							 ch.occurs = elist.occurs;
							 elist.occurs = ChildOccurs.oc_one;
						 }
						 if ((elist.parent !is null) && (elist.occurs == ChildOccurs.oc_one))
						 {
							 flatList ~= FelEntry(FelType.fel_element, ch);
						 }
						 else
						 {
							 flatList ~= FelEntry(FelType.fel_listbegin, elist);
							 flatList ~= FelEntry(FelType.fel_element, ch);
							 flatList ~= FelEntry(FelType.fel_listend, elist);
						 }
					 }
					 else
					 {
						 // list contains one list, so move it up to parent.
						 ChildElemList clist = cast(ChildElemList) ch;
						 if (clist.occurs==ChildOccurs.oc_one)
						 {
							 clist.occurs = elist.occurs;
							 elist.occurs = ChildOccurs.oc_one;
							 clist.parent = elist.parent;
							 appendFlatList(clist);
						 }
						 else
							 goto FULL_LIST;
					 }
					 return;
				 }
				 // label for goto
			 FULL_LIST:
				 flatList ~= FelEntry(FelType.fel_listbegin, elist);
				 foreach(ce ; elist.children)
				 {
					 if (ce.id !is null)
						 flatList ~= FelEntry(FelType.fel_element, ce);
					 else
					 {
						 ChildElemList cc = cast(ChildElemList) ce;
						 cc.parent = elist;
						 appendFlatList(cc);
					 }
				 }
				 flatList ~= FelEntry(FelType.fel_listend, elist);

			 }
		 }

		 void makeFlatList()
		 {
			 flatList.length = 0;
			 if (childList !is null)
				 appendFlatList(childList);
		 }

		 bool allowedChild(XmlString ename)
		 {
			 // search the tree to find a match
			 if (hasAny)
				 return true;
			 if (childList !is null)
			 {
				 if (flatList.length == 0)
					 makeFlatList();
				 foreach(s ; flatList)
				 {
					 if (s.fel == FelType.fel_element)
					 {
						 if (s.item.id == ename)
							 return true;
					 }
				 }
				 return false;
			 }
			 else
				 return false;
		 }


	}
    alias AttributeType[XmlString] AttributeTypeMap;
    alias AttributeDef[XmlString] AttributeDefMap;

    struct StringSet
    {
        bool[XmlString]	map;

		bool contains(const(T)[] name)
		{
			return (name in map) != null;
		}
        bool put(const(T)[] name)
        {
            bool* value = name in map;
            if (value !is null)
                return false;
            map[name.idup] = true;
            return true;
        }
        void remove(const(T)[] name)
        {
			// cheat
            map.remove(cast(immutable(T)[]) name);
        }
        void clear()
        {
            XmlString[] keys = map.keys();
            foreach(k ; keys)
                map.remove(k);
        }
    }

	class AttributeDef
	{
		/// The name
		XmlString		 id;
		/// What the DTD says it is
		AttributeType    dataform;
		/// Essential?
		AttributeDefault require;

		/// index of default value in values
		int    defaultIndex;
		/// list of allowed values, for particular AttributeType.
		XmlString[]     values;

		__gshared AttributeTypeMap    stdAttTypeList;

		__gshared static this()
		{
			stdAttTypeList["CDATA"] = AttributeType.att_cdata;
			stdAttTypeList["ID"] = AttributeType.att_id;
			stdAttTypeList["IDREF"] = AttributeType.att_idref;
			stdAttTypeList["IDREFS"] = AttributeType.att_idrefs;
			stdAttTypeList["ENTITY"] = AttributeType.att_entity;
			stdAttTypeList["ENTITIES"] = AttributeType.att_entities;
			stdAttTypeList["NMTOKEN"] = AttributeType.att_nmtoken;
			stdAttTypeList["NMTOKENS"] = AttributeType.att_nmtokens;
			stdAttTypeList["NOTATION"] = AttributeType.att_notation;
		}
		/// lookup for AttributeType from name.
		static bool getStdType(XmlString name, ref AttributeType val)
		{
			AttributeType* tt = name in stdAttTypeList;
			if (tt !is null)
			{
				val = *tt;
				return true;
			}
			return false;
		}

		bool         normalised;
		bool		 isInternal;
		AttributeList   attList;

		this(XmlString name)
		{
			id = name;
			defaultIndex = -1;
		}
	}


	/**
	* Has an ssociative array of AttributeDef objects by name.
	* Holds all the DTD definitions of attributes for an element type.
	* The idDef member holds the AttributeDef of associated ID attribute,
	*  if one was declared. The external member is used for validation against
	* standalone declarations.
	*/
	class AttributeList
	{
		XmlString		 id;
		//string  desc_; // unparsed list

		AttributeDefMap         attributes_;
		AttributeDef            idDef;
		bool					isInternal_;
		bool					isNormalised_;	 // all the values have had one time normalisation processing
		this(XmlString name)
		{
			id = name;
		}

	}
	/** XML and DTDs have ID and IDREF attribute types
	*  To fully validate these, need to collect all the values
	* of each element with an ID.
	* ID is the attribute which is supposedly unique, and only declared ID attribute one per element type.
	*
	* The IDValidation maps all the id attribute names, and all the elements
	*  refered to by any ID key value.
	*
	*  At the end of the parse, all the values in idReferences must have a mapped value in idElements.
	*  Do not need to keep all the idReferences.
	*  Once a mapping in idElements exists, the idReferences can be thrown away since it they have been validated.
	*  At the end of the  document idReferences.length should be zero.
	**/
	class IDValidate
	{
		/// contains the name of the id attribute by element name (one ID per element type)

		//string[string] idNames;
		XmlString[XmlString] idElements;
		int[XmlString]       idReferences;


		/// check uniqueness by returning false if ID value exists already
		/// delete existing references tally as these are validated
		/// etag is used to record the name of a clashing element
		bool mapElementID(XmlString etag, XmlString id)
		{
			auto idvalue = (id in idElements);
			if (idvalue !is null)
				return false;
			idElements[id] = etag;
			idReferences.remove(id);
			return true;
		}

		/// return true if the reference is not yet validated
		bool checkIDRef(XmlString refvalue)
		{
			auto idvalue = (refvalue in idElements);
			if (idvalue is null)
			{
				// referenced element not encountered (yet)
				auto ct = (refvalue in idReferences);
				if (ct !is null)
					*ct += 1;
				else
					idReferences[refvalue] = 1;
				return false;
			}
			return true;
		}
	}


	/// A single element name in a declaration list
    class ChildId
	{
		XmlString	id;
		ChildOccurs occurs;

		this()
		{
		}

		this(XmlString et)
		{
			id = et;
		}


	}

	/**
	Holds the Child elements, how many, what combinations,
	as set by the ELEMENT definition in the DTD,
	in a tree structure.

	*/
	class ChildElemList : ChildId
	{
		ChildElemList	parent;
		ChildOccurs		occurs;
		ChildSelect     select;
		ChildId[]		children;

		void append(ChildId ch)
		{
			children ~= ch;
		}

		@property auto length()
		{
			return children.length;
		}

		ChildId opIndex(size_t ix)
		{
			if (ix < children.length)
				return cast(ChildId) children[ix];
			else
				return null;
		}

		intptr_t firstIndexOf(XmlString name)
		{
			for(uintptr_t i = 0; i < children.length; i++)
				if (children[i].id == name)
					return i;
			return -1;
		}

		void addChildList(ChildElemList ch)
		{
			append(ch);
			ch.parent = this;
		}
		bool hasChild(XmlString name, bool recurse = true)
		{
			foreach(ce ; children)
			{
				if (ce.id !is null)
				{
					if (name == ce.id)
						return true;
				}
				else if (recurse)
				{
					ChildElemList list = cast(ChildElemList) ce;
					if (list !is null)
					{
						return list.hasChild(name);
					}
				}
			}
			return false;
		}
	}

    enum FelType
	{
			fel_listbegin,
			fel_listend,
			fel_element
	}

    struct FelEntry
	{
		FelType  fel;
		ChildId	 item;
	}


	XmlString toDTDString(FelEntry[] list, intptr_t itemIX)
	{
		XmlBuffer val;
		char     sep;
		FelType  lastItem;

		void printOccurs(ChildOccurs oc)
		{
			switch(oc)
			{
				case ChildOccurs.oc_zeroMany:
					val ~= '*';
					break;
				case ChildOccurs.oc_zeroOne:
					val ~= '?';
					break;
				case ChildOccurs.oc_oneMany:
					val ~= '+';
					break;
				case ChildOccurs.oc_one:
				default:
					break;
			}
		}
		auto limit = list.length;

		ChildElemList nlist, clist;
		int	  depth = 0;

		if (itemIX >= limit)
		{
			if (limit == 0)
				return "";
			else
				itemIX = 0;
		}
		FelEntry s = list[itemIX];
		while (s.fel != FelType.fel_listbegin)
		{
			itemIX--;
			s = list[itemIX];
		}
		lastItem = 	FelType.fel_listbegin;

		while(itemIX < limit)
		{
			s = list[itemIX++];
			switch(s.fel)
			{
				case FelType.fel_listbegin:
					val ~= '(';
					clist = cast(ChildElemList) s.item;
					depth++;
					sep = (clist.select == ChildSelect.sl_choice) ? '|' : ',';
					break;
				case FelType.fel_listend:
					val ~= ')';
					depth--;
					if (depth <= 0)
					{
						itemIX = cast(int) limit;
						break;
					}
					if (clist !is null)
					{
						printOccurs(clist.occurs);
						clist = (clist.parent !is null) ? cast(ChildElemList) clist.parent : null;
						if (clist !is null)
							sep = (clist.select == ChildSelect.sl_choice) ? '|' : ',';
					}
					break;
				case FelType.fel_element:
					if (lastItem != FelType.fel_listbegin)
						val ~= sep;
					ChildId child = cast(ChildId) s.item;
					val ~= child.id;
					printOccurs(child.occurs);
					break;
				default:
					break;
			}
			lastItem = s.fel;
		}
		return val.idup;
	}

	pure bool isURIScheme(XmlString scheme)
	{
		if (scheme.length == 0)
			return false;
		bool firstChar = true;
		foreach(dchar nc ; scheme)
		{
			if (firstChar)
			{
				firstChar = false;
				if (!isAlpha(nc))
					return false;
			}
			else
			{
				if (!isAlphaNum(nc))
				{
					switch(nc)
					{
						case '+':
						case '-':
						case '.':
							break;
						default:
							return false;
					}
				}
			}
		}
		return true;
	}

	/// name corresponds to some sort of URL
	bool isNameSpaceURI(XmlString name)
	{
		XmlString scheme, restof;

		auto sepct = splitNameSpace(name, scheme, restof);
		if (sepct == 0)
			return false;
		// scheme names are presumed to be ASCII
		if (!isURIScheme(scheme))
			return false;

		// check that the restof is ASCII
		foreach(dchar nc ; restof)
		{
			if (nc > 0x7F)
			{
				return false;
			}
		}
		return true;
	}

	/// more relaxed definition of IRI
	bool isNameSpaceIRI(XmlString name)
	{
		XmlString scheme, restof;

		auto sepct = splitNameSpace(name, scheme, restof);
		if (sepct == 0)
			return false;
		// scheme names are presumed to be ASCII
		if (!isURIScheme(scheme))
			return false;

		// TODO: no restrictions yet on restof

		return true;
	}

	/** Split string on the first ':'.
	*  Return number of ':' found.
	*  If no first splitting ':' found return nmSpace = "", local = name.
	*  If returns 1, and nmSpace.length is 0, then first character was :
	*  if returns 1, and local.length is 0, then last character was :
	**/
	intptr_t splitNameSpace(XmlString name, out XmlString nmSpace, out XmlString local)
	{
		intptr_t sepct = 0;

		auto npos = indexOf(name, ':');

		if (npos >= 0)
		{
			sepct++;
			nmSpace = name[0 .. npos];
			local = name[npos+1 .. $];
			if (local.length > 0)
			{
				XmlString temp = local;
				npos = indexOf(temp,':');
				if (npos >= 0)
				{
					sepct++;  // 2 is already too many
					//temp = temp[npos+1 .. $];
					//npos = indexOf(temp,':');
				}
			}
		}
		else
		{
			local = name;
		}
		return sepct;
	}
}// end template T
