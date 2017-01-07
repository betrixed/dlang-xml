module step0;

/**
	This downloads the antarctic2 sources, and reformats them 
	into a standard format.
	Line 1 , name and location
	* [ Year Month(8.1)x12 ]   blanks are '-'
*/
import std.stdio, std.file;
import std.path;
import std.algorithm;
import std.net.curl;
import std.conv;
import std.string;
import std.stdint;
import xml.txml;
import xml.util.bomstring;
import xml.xmlError;
import xml.sax;
import xml.util.buffer;

alias ReadRange!char  RData;
alias Buffer!char     WData;

string emptyNumber = "       -";

// includes linefeed, tab, carriage return
int getSpaceCt( ref RData idata, ref dchar lastSpace)
{
	int   count = 0;
	dchar space = 0x00;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x0A:
			case 0x09:
			case 0x0D:
				space = test;
				count++;
				idata.popFront();
				break;
			default:
				lastSpace = space;
				return count;
		}
	}
	return 0;
}
// same as getSpaceCt, but stop after first new line character
int getLineSpaceCt( ref RData idata, ref dchar lastSpace)
{
	int   count = 0;
	dchar space = 0x00;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x09:
			case 0x0D:
				space = test;
				count++;
				idata.popFront();
				break;
            case 0x0A:
                lastSpace = 0x0A;
                count++;
                return count;
			default:
				lastSpace = space;
				return count;
		}
	}
	return 0;
}
int getCharCt( ref RData idata, ref WData wdata)
{
	int count = 0;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x0A:
			case 0x09:
			case 0x0D:
				return count;
			default:
				wdata ~= test;
				count++;
				break;
		}
		idata.popFront;
	}
	return count;
}

bool stopAfterChar(ref RData idata, dchar c)
{
	while(!idata.empty)
	{
		dchar test = idata.front;
		if (test == c)
		{
			idata.popFront();
			return true;
		}
		idata.popFront();
	}
	return false;
}

bool getWordInLine(ref RData rd, const(char)[] myWord)
{
    dchar lastSpace = 0x00;
    Buffer!char buf;
    while(!rd.empty)
    {
        int spaceCt = getSpaceCt(rd,lastSpace);
        if (lastSpace == 0x0A)
        {
            return false;
        }
        buf.reset();
        int charCt = getCharCt(rd,buf);
        if (buf.data == myWord)
        {
            return true;
        }
    }
    return false;
}


bool isNumber(NumberClass nc)
{
    return (nc == NumberClass.NUM_INTEGER) || (nc == NumberClass.NUM_REAL);
}
void reparse(string txt, string basePath)
{
	int bomMark = BOM.NONE;
	auto f = readFileBom!char(txt,bomMark);

	WData wr;
	dchar lastSpace = 0;
	auto rd = RData(f);
	WData buf;
	RData number;

    NumberClass  nc;
    string stationName;

	while( !rd.empty)
	{
		int spaceCt = getSpaceCt(rd,lastSpace);

		// 1st text
		buf.reset();
		int charCt = getCharCt(rd,buf);
		if (buf.data == "SELECTED")
		{
			stopAfterChar(rd,0x0A);
			spaceCt = getSpaceCt(rd,lastSpace);

			buf.reset();
			charCt = getCharCt(rd,buf);
			wr ~= buf.data; // first part of name
			// keep going until get a number (a latitude)
			int locationCt = 0;
			while(locationCt < 2) //
			{
				spaceCt = getSpaceCt(rd,lastSpace);
				buf.reset();
				charCt = getCharCt(rd,buf);
				number.assign(buf.data.idup);
				buf.reset();
				nc = parseNumber(number,buf);
				if (isNumber(nc))
				{
                    if (locationCt == 0)
                    {
                        stationName = wr.data.idup;
                        wr ~= ", Location: ";
                    }
                    else
                        wr ~= ", ";

                    wr ~= buf.data;
                    spaceCt = getSpaceCt(rd,lastSpace);

                    buf.reset();
                    charCt = getCharCt(rd,buf);
                    number.assign(buf.data.idup);
                    buf.reset();
                    nc = parseNumber(number,buf);

                    if (isNumber(nc))
                    {
                       wr ~= 0x20;
                       wr ~= buf.data;
                       auto remains = number.data;
                       if (remains.length > 0) // NS, EW
                       {
                            wr ~= remains;
                       }
                       locationCt++;
                    }

				}
				else {
					// part of name
					wr ~= 0x20;
					wr ~= number.data;
				}
			}
			// end location

			spaceCt = getLineSpaceCt(rd, lastSpace);
			if (lastSpace != 0x0A)
			{
                buf.reset();
                charCt = getCharCt(rd, buf);
                if (charCt > 0)
                {
                    wr ~= ", ";
                    wr ~= buf.data;
                }
                // finish line
                stopAfterChar(rd,0x0A);
            }
            // consume month headers line
            uintptr_t monthOffset = getSpaceCt(rd,lastSpace);
            // get the distance between the month columns

            charCt = getCharCt(rd, buf);
            spaceCt = getSpaceCt(rd, lastSpace);

            uintptr_t colWidth = charCt + spaceCt;

            uintptr_t firstGap = monthOffset - colWidth - 4;

            // if the header line does not end with "MEAN" then colWidth is 8
            bool isSqueezed = getWordInLine(rd,"MEAN");
            if (isSqueezed)
            {
                stopAfterChar(rd,0x0A);
            }
            else {
                // colwidth is 8, monthOffset is off by 4
                monthOffset -= 4;
                colWidth = 8;
                firstGap = 0;
            }
            // read year(4), and 12 months (8)
            spaceCt = getSpaceCt(rd,lastSpace); // should be zero
            buf.reset();
            nc = parseNumber(rd,buf);
            while (nc == NumberClass.NUM_INTEGER)
            {
                // new line
                wr ~= '\n';
                wr ~= buf.data; // TODO : check length == 4?

                // go to the first month and jump any gap
                rd.assign(rd.data[firstGap..$]);

                //spaceCt = getSpaceCt(rd, lastSpace);

                for(int i = 0; i < 12; i++)
                {
                    number.assign(rd.data[0..colWidth]); // TODO: data.length >= 8?
                    spaceCt = getSpaceCt(number,lastSpace);

                    buf.reset();
                    nc = parseNumber(number, buf);
                    if (isNumber(nc))
                    {
                        auto len = buf.data.length;
                        spaceCt = (len <= 8) ? cast(int)(8 - len) : 0;
                        for(int k=0; k<spaceCt; k++)
                            wr ~= cast(char)0x20;
                        wr ~= buf.data;
                    }
                    else {
                        for(int k=0; k<7; k++)
                            wr ~= cast(char)0x20;
                        wr ~= "-";
                    }
                    rd.assign(rd.data[colWidth..$]); // advance along
                }
                // goto next year/line
                stopAfterChar(rd,0x0A);
                spaceCt = getSpaceCt(rd,lastSpace);
                buf.reset();
                nc = parseNumber(rd,buf);
            }
            // done after no more years
            break;
		}

	}
    if (stationName.length > 0)
    {
        stationName = tr(stationName, " ", "_");
        auto filename = text(basePath,stationName,".txt");
        auto fout = File(filename,"w");
        fout.write(wr.data);
        fout.close();
    }
}
void main(string[] argv)
{

	string[] sources;

	auto tfiles = dirEntries("temp_html","*.txt",SpanMode.depth);
	string outputDir = "antartic2/";
	foreach(f; tfiles)
	{
		sources ~= f.name;
	}
    sources.sort!("a < b");
	foreach(s; sources)
	{
		writeln("src: ", s);
		reparse(s, outputDir);
	}
}
