module main;

/**
	Merges multiple files for 1 station,
	in argument order replacement.
	Files in standard format.
	Line 1 , name and location
	* [ Year Month(8.1)x12 ]   blanks are '-'
	Used for 3 byrd data sets, - byrd_1.txt, byrd_r.txt, byrd_3.txt.
	Output byrd_merge.txt
	Ouput to replace Byrd.All.temperature.txt in antarctic1

*/
import std.stdio, std.file;
import std.path;
import std.algorithm;
import std.net.curl;
import std.conv;
import std.string;
import std.stdint;
import std.format;
import std.math;
import texi.read;
import texi.buffer;
import texi.bomstring;

alias ReadRange!char RData;
alias Buffer!char  WData;


class StationYear {
	uint 	   year;
	string[12] monthData;

	this(uint yr, string[12] mdata)
	{
		year = yr;
		monthData = mdata;
	}

	this(uint yr)
	{
		year = yr;
	}

};

StationYear[uint]  gData; //Assoc array of each years data.


void saveYearData(ref RData rd)
{
	WData wbuf;

	if (getToNewLine(rd,wbuf))
	{
		RData line = wbuf.data.idup;
		wbuf.reset();
		int charCt = getCharCt(line,wbuf);
		uint year = to!uint(wbuf.data);
		dchar lastChar;
		string[12] monthData;
		bool hasValue = false;
		foreach( k ; 0..12)
		{
			int spaceCt = getSpaceCt(line,lastChar);
			if (lastChar == 0x0A)
			{
				break; // no more in line??
			}
			wbuf.reset();
			charCt = getCharCt(line,wbuf);
			if ((charCt==1)&&(wbuf.data == "-"))
			{
				monthData[k] = [];
			}
			else {
				double dval = to!double(wbuf.data);
				if (fabs(dval) < 900.0)
				{
					monthData[k] = wbuf.data.idup;
					hasValue = true;
				}
			}
		}
		if (hasValue)
		{
			StationYear y = gData.get(year,null);

			if (y is null)
			{
				gData[year] = new StationYear(year,monthData);
			}
			else {
				// overwrite with new none empty values;
				foreach(k ; 0..12)
				{
					if (monthData[k])
					{
						y.monthData[k] = monthData[k];
					}
				}
			}
		}
	}
}
void main(string[] argv)
{

	string[] sources;
	string   output;



	auto argCt = argv.length;
	uintptr_t k = 1;
	while (k < argCt)
	{
		string arg = argv[k];
		if (arg == "--output")
		{

			if (k < argCt-1)
			{
                k++;
				output = argv[k];
            }
		}
		else
		{
		 	if (!exists(arg))
			{
				writeln("cannot read file: ", arg);
				return;
			}
			sources ~= arg;
		}
		k++;
	}
	if (sources.length == 0 || output.length == 0)
	{
		writeln("<merge> --output [outfile]  *[sourcefiles]");
		return;
	}
	auto fout = File(output,"w");

    int filect = 0;
    WData wbuf;
	foreach(s ; sources)
	{
        filect++;
		int bomMark = BOM.NONE;
		auto fin = readFileBom!char(s,bomMark);
		RData rd = fin;


		if (getToNewLine(rd,wbuf))
		{
			if (filect == 1)
			{
				fout.writeln(wbuf.data);
			}
		}
		// read each years data, check for empty
		while(!rd.empty)
		{
			saveYearData(rd);
		}
	}
	// write merged data
	// order by year
	auto ykeys = gData.keys();
	ykeys.sort!("a < b");
	FormatSpec!char mspec;
	mspec.spec = 's';
	mspec.width = 8;

	foreach(y ; ykeys)
	{
		wbuf.reset();
		wbuf ~= to!string(y);
		auto sy = gData[y];

		foreach(m ; 0..12)
		{
			auto val = sy.monthData[m];
			if(!val)
			{
				val = "-";
			}
			formatValue(wbuf.writer,val,mspec);

		}
		fout.writeln(wbuf.data);
	}
	fout.close();
	writeln("All Done : ", ykeys.length, " years");
	getchar();
}
