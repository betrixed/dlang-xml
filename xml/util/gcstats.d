module xml.util.gcstats;

/**
	Mixin to be added. Assumes no other default constructor, and not added at other places in inheritance.
	Other constructors may need tweeking. Implementation can be made more sophisticated.
*/
// derive class from this, to check on garbage collection success.
import std.stdio;
import std.algorithm;

class GCStatsSum {
	string	id;
	ulong sCreated;
	ulong sDeleted;

	__gshared GCStatsSum[] gAllStats;

	this()
	{
		gAllStats ~= this;
	}

    void inc()
	{
		sCreated++;
	}
    void dec()
	{
		sDeleted++;
	}
    void stats(ref ulong created, ref ulong deleted) const
	{
		created = sCreated;
		deleted = sDeleted;
	}

	void output() const
	{

		if (id)
			write(id);
		else
			write(" no id");

		auto diff = sCreated- sDeleted;
		double alivepc = sCreated > 0 ? (diff * 100.0) / sCreated : 0.0;

		writeln(" created: ", sCreated, " deleted: ", sDeleted, " diff: ", diff, " alive % ", alivepc);
	}

	static bool statsLess(GCStatsSum a, GCStatsSum b)
	{
		auto adiff = a.sCreated - a.sDeleted;
		auto bdiff = b.sCreated - b.sDeleted;
		return (adiff < bdiff) ? true : false;
	}

	static void AllStats()
	{
		ulong tCreate, tDelete;
		ulong sCreate, sDelete;

		sort!(statsLess)(gAllStats);

		foreach(st ; gAllStats)
		{
			st.stats(sCreate,sDelete);
			tCreate += sCreate;
			tDelete += sDelete;

			st.output();
		}
		auto diff = tCreate- tDelete;
		double alivepc = tCreate > 0 ? (diff * 100.0) / tCreate : 0.0;
		writeln("All created: ", tCreate, " deleted: ", tDelete, " diff: ", diff, " alive % ", alivepc);
	}
}


mixin template GC_statistics()
{
	static GCStatsSum	gcStatsSum;

	static this()
	{
		gcStatsSum = new GCStatsSum();
	}

	static void setStatsId(string id)
	{
		gcStatsSum.id = id;
	}

	/**
	In objects that use GC_STATS, require in this
    version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}

	---
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
	---
	*/
	static void gcStats(ref ulong created, ref ulong deleted)
	{
		gcStatsSum.stats(created,deleted);
	}

}
