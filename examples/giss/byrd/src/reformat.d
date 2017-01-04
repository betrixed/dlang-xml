module reformat;
import std.file;
import std.stdio;

import xml.util.bomstring;
import xml.textInput;
import xml.util.buffer;
import xml.txml;


alias ReadRange!char  IData;
alias Buffer!char     WData;

// includes linefeed, tab, carriage return
int getSpaceCt( ref IData idata, ref dchar lastSpace)
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


int getCharCt( ref IData idata, ref WData wdata)
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

void main(string[] argv)
{
	
	// convert byrd.txt into 
	// Byrd.All.temperature.txt

	// read the entire source file
	string inputFile = "byrd.txt";
	string outputFile = "Byrd.All.Temperature.txt";

	if (!exists(inputFile))
    {
        writeln("File not found : ", inputFile, "from ", getcwd());
        //getchar();
        return;
    }
    int bomMark = BOM.NONE;
	
	auto inputData = readFileBom!char(inputFile,bomMark);

	auto ir = IData(inputData);

	Buffer!char   bout;
	Buffer!char   token;

	dchar lastSpace = 0x00;
	bool lineStart = true;
	bool colHeader = false;
	bout ~= "Byrd temperature";
	while(!ir.empty)
	{
		int spaceCt = getSpaceCt(ir,lastSpace);
		bool isNewLine = (spaceCt > 0) && ((lastSpace==0x0D) || (lastSpace==0xA));
		if (isNewLine)
		{
			bout ~= '\n';
			lineStart = true;
		}
		token.reset();
		int tokenCt = getCharCt(ir, token);

		if (lineStart)
		{
			lineStart = false;
			colHeader = (token.data == "Year");
			if (!colHeader)
			{				
				bout ~= token.data;
			}
			
		}
		else if (!colHeader) {
			
			if (token.data == "-999.0")
			{
				token.reset();
				token ~= "       -";
			}
			else while (tokenCt < 8)
			{
				tokenCt++;
				bout ~= 0x20;
			}
			bout ~= token.data;
		}
	}

	auto f = File(outputFile,"w");

	f.write(bout.data);

	f.close();

	// input format first line "Year", 4 char field
	// then 12 7-character fields , Jan - Dec
	// then year, 12 numbers


}