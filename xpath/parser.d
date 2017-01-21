module xpath.parser;

import std.stdint;
import std.range;
import std.range.interfaces;
import std.string;

import texi.read;
import texi.buffer;
import xml.xmlChar;

alias pure bool function(dchar) CharTestFunc;

/// PathExpression execution error
class XPathRunError : Error
{
    this(string msg)
    {
        super(msg);
    }
}
/// XPath parser error
class XPathSyntaxError : Error
{
    this(string msg)
    {
        super(msg);
    }
}

class XPathParse : ParseInputRange
{
protected:
    CharTestFunc startTest;
    CharTestFunc nameTest;
    bool		 isNSAware;
public:

	void setNSAware(bool nsAware)
	{
		if (nsAware)
		{	// ':' characters are special
        	startTest = &isNameStartChar11;
        	nameTest = &isNameChar11;
		}
		else { // ':' characters are not special
        	startTest = &isNameStartChar10;
        	nameTest = &isNameChar10;
		}
		isNSAware = nsAware;
	}
    this(InputRange!dchar ir)
    {
        super(ir);
        setNSAware(true);

    }



    bool getAttribute(ref string atname, ref string atvalue)
    {
        Buffer!char temp;
        intptr_t pos;
        getSpaceCt();
        if (getQName(temp, pos))
        {
            getSpaceCt();
            if (match('='))
            {
                getSpaceCt();
                dchar test = front;
                atname = temp.data.idup;
                if (test=='\"' || test == '\'')
                {
                    temp.reset();
                    if (unquote(temp))
                    {
                        atvalue = temp.data.idup;
                        return true;
                    }
                }
            }
        }
        return false;
    }


    bool getQName(W)( ref W wr, ref intptr_t prefixIX)
    {
        wr.reset();
        if (empty || !startTest(front))
        {
            return false;
        }
        wr.put(front);
        popFront();
        prefixIX = -1;
        while(!empty)
        {
            if (front == ':')
            {
                if (prefixIX >= 0)
                    break;
                popFront();
                if (front == ':')
                {
                    pushFront(':');
                    break;
                }
                prefixIX = wr.length;
                wr.put(':');
            }
            if (nameTest(front))
                wr.put(front);
            else
                break;
            popFront();
        }
        return true;
    }


    bool getQName(W)(ref W opt)
    {
        if (empty)
            return false;
        if (!startTest(front))
            return false;
        opt.put(front);
        popFront();
        while (!empty)
        {
            if (nameTest(front))
            {
                opt.put(front);
                popFront();
            }
            else
                break;
        }
        return true;
    }
}
