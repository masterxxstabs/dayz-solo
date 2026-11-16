class SoloDaysEntry
{
	string Uid;
	float Minutes;
}

class SoloDaysFile
{
	ref array<ref SoloDaysEntry> Players;

	void SoloDaysFile()
	{
		Players = new array<ref SoloDaysEntry>;
	}
}

// Counts the in-game time each character has stayed alive, from the world clock, so night
// speed-ups and sleeping skips count too. Kept in the profile, not in the world save: adding
// data to saved items would make existing worlds unreadable.
class SoloDayCounter
{
	protected const string DAYS_PATH = "$profile:SoloSurvivor/days.json";
	protected const int MAX_STEP_MINUTES = 720;
	protected const int SAVE_EVERY_TICKS = 6;

	protected ref SoloDaysFile m_File;
	protected ref map<string, int> m_LastClock;
	protected int m_TicksSinceSave;

	void SoloDayCounter()
	{
		m_File = new SoloDaysFile();
		m_LastClock = new map<string, int>;
		if (FileExist(DAYS_PATH))
		{
			string loadError;
			if (!JsonFileLoader<SoloDaysFile>.LoadFile(DAYS_PATH, m_File, loadError))
				Print("[SoloSurvivor] " + loadError);
		}
		if (!m_File.Players)
			m_File.Players = new array<ref SoloDaysEntry>;
	}

	// Month and day only: a jump (new month, server restart on the PC clock) is skipped, not counted.
	protected int ClockMinutes()
	{
		int year, month, day, hour, minute;
		GetGame().GetWorld().GetDate(year, month, day, hour, minute);
		return ((month * 31) + day) * 1440 + hour * 60 + minute;
	}

	protected SoloDaysEntry FindEntry(string uid)
	{
		foreach (SoloDaysEntry entry : m_File.Players)
		{
			if (entry.Uid == uid)
				return entry;
		}
		SoloDaysEntry added = new SoloDaysEntry();
		added.Uid = uid;
		added.Minutes = 0;
		m_File.Players.Insert(added);
		return added;
	}

	static int DayOf(float minutes)
	{
		int fullDays = minutes / 1440;
		return fullDays + 1;
	}

	void Tick()
	{
		int now = ClockMinutes();
		array<Man> players = new array<Man>;
		GetGame().GetPlayers(players);
		foreach (Man man : players)
		{
			PlayerBase player = PlayerBase.Cast(man);
			if (!player || !player.GetIdentity())
				continue;

			string uid = player.GetIdentity().GetId();
			SoloDaysEntry entry = FindEntry(uid);
			if (!player.IsAlive())
			{
				entry.Minutes = 0;
				m_LastClock.Remove(uid);
				continue;
			}

			if (m_LastClock.Contains(uid))
			{
				int step = now - m_LastClock.Get(uid);
				if (step > 0 && step <= MAX_STEP_MINUTES)
					entry.Minutes = entry.Minutes + step;
			}
			m_LastClock.Set(uid, now);
			SendTo(player, entry);
		}

		m_TicksSinceSave++;
		if (m_TicksSinceSave >= SAVE_EVERY_TICKS)
			Save();
	}

	void SendTo(PlayerBase player, SoloDaysEntry entry)
	{
		Param1<int> data = new Param1<int>(DayOf(entry.Minutes));
		GetGame().RPCSingleParam(player, SOLO_DAYS_RPC, data, true, player.GetIdentity());
	}

	void ResetPlayer(string uid)
	{
		FindEntry(uid).Minutes = 0;
		m_LastClock.Remove(uid);
		Save();
	}

	void ForgetClock(string uid)
	{
		m_LastClock.Remove(uid);
		Save();
	}

	void Save()
	{
		m_TicksSinceSave = 0;
		string saveError;
		JsonFileLoader<SoloDaysFile>.SaveFile(DAYS_PATH, m_File, saveError);
	}
}
