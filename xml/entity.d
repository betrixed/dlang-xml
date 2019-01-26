module entity;

import std.conv;

enum EntityType { Parameter, General, Notation }
enum RefTagType { UNKNOWN_REF, ENTITY_REF, SYSTEM_REF, NOTATION_REF}

struct ExternalID(T)
{
    immutable(T)[] publicId_;
    immutable(T)[] systemId_;
}

class EntityData(T)
{
    enum
    {
        Unknown, Found, Expanded, Failed
    }


    immutable(T)[] 		name_;				// key for AA lookup
    immutable(T)[] 		value_;				// processed value
    ExternalID!T		src_;				// public and system id
    EntityType		etype_;				// Parameter, General or Notation?
    RefTagType		reftype_;			// SYSTEM or what?
    int				status_;			// unknown, found, expanded or failed
    bool			isInternal_;	    // This was defined in the internal subset of DTD

    immutable(T)[] 			encoding_;		// original encoding?
    immutable(T)[] 			version_;	    // xml version ?
    immutable(T)[] 			ndataref_;		// name of notation data, if any

    //Notation		ndata_;         // if we are a notation, here is whatever it is
    string			baseDir_;		// filesystem path to folder
    EntityData		context_;		// if the entity was declared in another entity


    ~this()
    {

    }
    this(immutable(T)[] id, EntityType et)
    {
        name_ = id;
        etype_ = et;
        status_ = EntityData.Unknown;
    }

    @property void value(const(T)[] s)
    {
        value_ = to!(immutable(T)[])(s);
    }
    @property immutable(T)[] value()
    {
        return value_;
    }
}
