module xml.dtd;
/**
These data structures are seperate from other parts of regular DOM
*/
import xml.error;
import xml.txml;
import std.stdint, std.conv, std.array;
import std.ascii;
import std.string;
import xml.entity;
import std.array;

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
class DocTypeData(T)
{
    alias immutable(T)[]	XmlString;
    alias EntityData!T[ XmlString ] EntityDataMap;

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
    ExternalID!T			src_;
    //bool				resolved_;
    bool				isInternal_;
    bool				undeclaredInvalid_;	// undeclared entity references are invalid instead of not-wf? Errata 3e E13
    //DocumentType	docTypeNode_; // DOM interface

    EntityDataMap		paramEntityMap;
    EntityDataMap 		generalEntityMap;
    EntityDataMap		notationMap;

    ElementDef!T[ XmlString]		elementDefMap;
    AttributeList!T[ XmlString ]	attributeListMap;

    XmlString[XmlString]				elementIDMap;

    EntityData!T getEntity(const(T)[] name, bool isPE = false)
    {
        auto pdef = isPE ? name in paramEntityMap : name in generalEntityMap;
        return (pdef is null) ? null : *pdef;
    }
}

class ElementDef(T)
{
    alias immutable(T)[]	XmlString;
    XmlString   id;

    AttributeList!T   attrList;
    //string   desc_;
    bool    hasPCData;
    bool    hasElements;
    bool    hasAny;
    bool    isInternal;

    FelEntry!T[]				flatList;
    ChildElemList!T			    childList; // this may be chucked away


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
     package void appendFlatList(ChildElemList!T elist)
     {
         if (elist.children.length > 0)
         {
             if (elist.children.length == 1)
             {
                 // single list or single item
                 ChildId!T ch = elist.children[0];
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
                         flatList ~= FelEntry!T(FelType.fel_element, ch);
                     }
                     else
                     {
                         flatList ~= FelEntry!T(FelType.fel_listbegin, elist);
                         flatList ~= FelEntry!T(FelType.fel_element, ch);
                         flatList ~= FelEntry!T(FelType.fel_listend, elist);
                     }
                 }
                 else
                 {
                     // list contains one list, so move it up to parent.
                     ChildElemList!T clist = cast(ChildElemList!T) ch;
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
             flatList ~= FelEntry!T(FelType.fel_listbegin, elist);
             foreach(ce ; elist.children)
             {
                 if (ce.id !is null)
                     flatList ~= FelEntry!T(FelType.fel_element, ce);
                 else
                 {
                     ChildElemList!T cc = cast(ChildElemList!T) ce;
                     cc.parent = elist;
                     appendFlatList(cc);
                 }
             }
             flatList ~= FelEntry!T(FelType.fel_listend, elist);

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


struct StringSet(T)
{
    bool[ immutable(T)[] ]	map;

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
        immutable(T)[][] keys = map.keys();
        foreach(k ; keys)
            map.remove(k);
    }
}
enum AttributeType
{
    att_cdata,
    att_id,
    att_idref,
    att_idrefs,
    att_entity,
    att_entities,
    att_nmtoken,
    att_nmtokens,
    att_notation,
    att_enumeration
}







class AttributeDef(T)
{
    alias immutable(T)[] XmlString;
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

    __gshared AttributeType[XmlString] stdAttTypeList;

    static this() {
        stdAttTypeList = [
            "CDATA" : AttributeType.att_cdata,
            "ID" : AttributeType.att_id,
            "IDREF" : AttributeType.att_idref,
            "IDREFS" : AttributeType.att_entity,
            "ENTITY" : AttributeType.att_entity,
            "ENTITIES" : AttributeType.att_entities,
            "NMTOKEN" : AttributeType.att_nmtoken,
            "NMTOKENS" : AttributeType.att_nmtokens,
            "NOTATION" : AttributeType.att_notation
         ];

    }

    /// lookup for AttributeType from name.
    static bool getStdType(XmlString name, ref AttributeType val)
    {
        const AttributeType* tt = name in stdAttTypeList;
        if (tt !is null)
        {
            val = *tt;
            return true;
        }
        return false;
    }

    bool         normalised;
    bool		 isInternal;
    AttributeList!T   attList;

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
class AttributeList(T)
{
    alias immutable(T)[]	XmlString;
    XmlString		 id;
    //string  desc_; // unparsed list

    AttributeDef!T[ XmlString ]        attributes_;
    AttributeDef!T           idDef;
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
class IDValidate(T)
{
    /// contains the name of the id attribute by element name (one ID per element type)
    alias immutable(T)[] XmlString;

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

class ChildId(T)
{
    immutable(T)[]	id;
    ChildOccurs occurs;

    this()
    {
    }

    this(immutable(T)[] et)
    {
        id = et;
    }
}

/**
Holds the Child elements, how many, what combinations,
as set by the ELEMENT definition in the DTD,
in a tree structure.

*/
class ChildElemList(T) : ChildId!T
{

    ChildElemList!T	parent;
    ChildOccurs		occurs;
    ChildSelect     select;
    ChildId!T[]		children;

    void append(ChildId!T ch)
    {
        children ~= ch;
    }

    @property auto length()
    {
        return children.length;
    }

    ChildId!T opIndex(size_t ix)
    {
        if (ix < children.length)
            return cast(ChildId!T) children[ix];
        else
            return null;
    }

    intptr_t firstIndexOf(immutable(T)[] name)
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
    bool hasChild(immutable(T)[] name, bool recurse = true)
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

struct FelEntry(T)
{
    FelType    fel;
    ChildId!T  item;
}

template XMLDTD(T) {
	/// A single element name in a declaration list
    alias immutable(T)[] XmlString;

    alias sxml!T.XmlBuffer  XmlBuffer;


	XmlString toDTDString(FelEntry!T[] list, intptr_t itemIX)
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

		ChildElemList!T nlist, clist;
		int	  depth = 0;

		if (itemIX >= limit)
		{
			if (limit == 0)
				return "";
			else
				itemIX = 0;
		}
		FelEntry!T s = list[itemIX];
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
					clist = cast(ChildElemList!T) s.item;
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
						clist = (clist.parent !is null) ? cast(ChildElemList!T) clist.parent : null;
						if (clist !is null)
							sep = (clist.select == ChildSelect.sl_choice) ? '|' : ',';
					}
					break;
				case FelType.fel_element:
					if (lastItem != FelType.fel_listbegin)
						val ~= sep;
					auto child = cast(ChildId!T) s.item;
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
}
