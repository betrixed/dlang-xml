module hpberg;
/**
	read the t_hohenpeissenberg.txt monthly averages, convert to v2 format
	optional argument, omit years earlier than arg1.
	This script is not needed any more, as the ghcn includes this data
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

string HPBERG_ID = "61710962000";

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

	// format a line into write buffer w.
	void v2_format(ref WData w)
	{
		FormatSpec!char mspec;
		mspec.spec = 's';
		mspec.width = 5;

		w.reset();
		w ~= text(HPBERG_ID,to!string(year));

		foreach(m ; 0..12)
		{
			auto val = monthData[m];
			if(!val)
			{
				val = "-9999";
			}
			else {
				double test = to!double(val) * 10.0;
				if (fabs(test) > 900.0)
				{
					val = "-9999";
				}
				else {
					long temp = lround(test);
					val = to!string(temp);
				}
			}
			formatValue(w.writer,val,mspec);
		}
	}
};




void main(string[] argv)
{

	string[] sources;
	string   output = "hohenpeissenberg.v2";
	string   input = "t_hohenpeissenberg.txt";
	uint minYear = 0;

	auto argCt = argv.length;
	uint  ag = 1;
	while (ag < argCt)
	{
		string arg = argv[ag];
		if (arg == "--minyear")
		{

			if (ag < argCt-1)
			{
                ag++;
				minYear = to!uint(argv[ag]);
            }
		}
		else if (arg == "--output")
		{
			if (ag < argCt-1)
			{
                ag++;
				output = argv[ag];
            }
		}
		else if (arg == "--input")
		{
			if (ag < argCt-1)
			{
                ag++;
				input = argv[ag];
            }

		}
		ag++;
	}
 	if (!exists(input))
	{
		writeln("cannot read file: ", input);
		return;
	}

	int bomMark = BOM.NONE;
	auto fin = readFileBom!char(input,bomMark);
	auto fout = File(output,"w");
	RData rd = fin;
	WData wbuf;

	int yearCt = 0;
	if (stopAfterChar(rd,0x0A)) // strip first line
	{
		dchar lastChar = 0x00;
		int spCt = 0;
		int charCt = 0;

		while(!rd.empty)
		{

			spCt = getSpaceCt(rd,lastChar);
			wbuf.reset();
			charCt = getCharCt(rd, wbuf);
			if (charCt == 4)
			{
				uint aYear = to!uint(wbuf.data);
				uint monthCt = 0;
				if (aYear >= minYear)
				{
					StationYear sy = new StationYear(aYear);
					foreach(k ; 0..12)
					{
						spCt = getSpaceCt(rd,lastChar);
						wbuf.reset();
						charCt = getCharCt(rd,wbuf);
						if ((charCt==1)&&(wbuf.data=="-"))
						{
							sy.monthData[k] = [];
						}
						else {
							monthCt++;
							sy.monthData[k] = wbuf.data.idup;
						}
					}
					if (monthCt > 0)
					{
						yearCt++;
						wbuf.reset();
						sy.v2_format(wbuf);
						fout.writeln(wbuf.data);
					}
					destroy(sy);
				}
                stopAfterChar(rd,0x0A); // finish the line
			}
		}
	}
	fout.close();
	writeln("years ct = ",yearCt);

}
