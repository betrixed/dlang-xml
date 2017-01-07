module mergev2;

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

class FileV2 {
	RData rd;
	WData line;
	uint  year;
	const(char)[] id;
	string name;
	const(char)[] data;

	this(string fileName)
	{
		int bomMark = BOM.NONE;
		name = fileName;
		auto data = readFileBom!char(name,bomMark);
		rd.assign(data);
	}

	bool empty() @property
	{
		return (rd.empty) && (year==0);
	}

	bool nextLine()
	{
		if (rd.empty)
		{
			year = 0;
			return false;
		}
		line.reset();
		if (getToNewLine(rd,line))
		{
			data = line.data;
			if (data.length == 76 )
			{	// country code (3), wmo (5), station classifier(3), duplicate code(1), year(4) 
				id = data[0..16];
				year = to!uint(id[12..16]);
				return true;
			}
		}
		year = 0;
		data = [];
		return false;		
	}

};

struct WorkFlow {
	string   output;
	string   input1;
	string	 input2;
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
			else if (arg == "--f1")
			{
				if (ag < argCt-1)
				{
	                ag++;
					input1 = argv[ag];
	            }

			}
			else if (arg == "--f2")
			{
				if (ag < argCt-1)
				{
	                ag++;
					input2 = argv[ag];
	            }

			}
			ag++;
		}
	}
	bool checkArgs()
	{
	 	if (!exists(input1))
		{
			writeln("cannot read file: ", input1);
			return false;
		}
	 	if (!exists(input2))
		{
			writeln("cannot read file: ", input2);
			return false;
		}
		if (minYear==0)
			minYear = 1880;
		if (!output)
		{
			output = stripExtension(input1) ~ "_comb.v2";
		}
		return true;
	}

	void printArgs()
	{
		writeln(program);
		writeln(" --f1 filepath");
		writeln(" --f2 filepath");
		writeln(" --output filepath");
		writeln(" --minyear 1880");		
	}

	void process()
	{
		File fout = File(output,"w");
		File ferr = File("conflicts.v2","w");
		uint stripCt = 0;

		FileV2 rd1 = new FileV2(input1);
		FileV2 rd2 = new FileV2(input2);

		rd1.nextLine();
		rd2.nextLine();
		uint mergeCt = 0;
		uint dupCt = 0;
		while(rd1.year || rd2.year)
		{	
			mergeCt++;
			if (rd1.year && rd2.year)
			{
				if (rd1.id < rd2.id)
				{
					fout.writeln(rd1.data);
					rd1.nextLine();
				}	
				else if (rd2.id < rd1.id)
				{
					fout.writeln(rd2.data);
					rd2.nextLine();
				}
				else {
					// notify duplication conflict, at least one version must be written, 
					// both lines advanced
					fout.writeln(rd2.data);
					if (rd2.data != rd1.data)
					{
						dupCt++;
						ferr.writeln(rd1.data);
						ferr.writeln(rd2.data);
					}
					rd1.nextLine();
					rd2.nextLine();
				}
			}
			else if (rd1.year)
			{
				fout.writeln(rd1.data);
				rd1.nextLine();
			}
			else {
				fout.writeln(rd2.data);
				rd2.nextLine();
			}
		}
		fout.close();
		ferr.close();
		writeln(mergeCt, " lines written");
		writeln(dupCt, " data conflicts of station-year");
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