module dump_old;

/**
	read v2 format monthly averages from input, 
	output only lines such that year >= minYear

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

struct WorkFlow {
	string   output;
	string   input;
	uint     minYear;
	string	 program;

	void fetchArgs(string[] argv)
	{
		auto argCt = argv.length;
		uint  ag = 1;

		program = baseName(argv[0]);
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
	}
	bool checkArgs()
	{
	 	if (!exists(input))
		{
			writeln("cannot read file: ", input);
			return false;
		}
		if (minYear==0)
			minYear = 1880;
		if (!output)
		{
			output = stripExtension(input) ~ "_strip.v2";
		}
		return true;
	}

	void printArgs()
	{
		writeln(program);
		writeln(" --input filepath");
		writeln(" --output filepath");
		writeln(" --minyear 9999");		
	}

	void process()
	{
		int bomMark = BOM.NONE;
		auto fin = readFileBom!char(input,bomMark);
		RData rd = fin;
		WData wbuf;
		File fout = File(output,"w");
		uint stripCt = 0;
		while(!rd.empty)
		{
			wbuf.reset();
			if (getToNewLine(rd,wbuf))
			{
				auto data = wbuf.data;
				if (data.length == 76 )
				{
					auto yearNum = to!uint(data[12..16]);
					if (yearNum >= minYear)
					{
						fout.writeln(data);
						stripCt++;
					}
				}
			}
		}
		fout.close();
		writeln(stripCt, " lines stripped");
	}

};

void main(string[] argv)
{

	WorkFlow w;

	w.fetchArgs(argv);
	if (!w.checkArgs())
	{	
		w.printArgs();
		return;
	}
	w.process();

}