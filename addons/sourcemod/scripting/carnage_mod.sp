#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <smlib>
#include <clientprefs>

#define m_flNextSecondaryAttack FindSendPropInfo("CBaseCombatWeapon", "m_flNextSecondaryAttack") 

#pragma semicolon 1
#pragma newdecls required

//Plugin variables
int g_Round = 0;
bool g_NoScope = false, g_bForceCarnage[MAXPLAYERS+1] = false, g_bKnifeDamage = false;
char Prefix[100];

//Song Path Variables
char gs_SongPath[256];
char CarnageSong[6][256];
int songsfound = 0;
char song[64];
int randomsong = 0;
float g_fVolume = 0.05;

//Cvars
ConVar g_EveryWhichRound, g_ADMINFLAG, g_SongPath, g_SongVolume, g_Prefix, g_KnifeDamage, g_AutoBhop, g_CommandName;

//ClientPrefs
Handle Handle_BSM;
bool bsm[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "[CSGO] Carnage Round", 
	author = "Elitcky, Cruze",
	description = "Noscope Rounds every X rounds.",
	version = "1.5",
	url = "http://steamcommunity.com/id/stormsmurf2 ; http://steamcommunity.com/profiles/76561198132924835"
};

public void OnPluginStart()
{
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_end", OnRoundEnd);

	RegConsoleCmd("sm_bsm", CMD_BSM);
	
	Handle_BSM = RegClientCookie("Bhop Sound Mute", "Sound setting", CookieAccess_Private);

	g_EveryWhichRound = CreateConVar("sm_carnage_round", "5", "Interval between carnage rounds.");
	g_ADMINFLAG = CreateConVar("sm_carnage_flag", "z", "Flag for force carnage command.");
	g_SongPath = CreateConVar("sm_carnage_song", "misc/carnageround/ronda_carnageR.mp3,misc/carnageround/ronda_carnage2R.mp3", "DON'T USE SPACE BETWEEN \",\"");
	g_SongVolume = CreateConVar("sm_carnage_song_volume", "0.05", "Volume of song(s).");
	g_Prefix = CreateConVar("sm_carnage_prefix", "{green}[CARNAGE]{default}", "Change plugin's prefix of chat messages.");
	g_KnifeDamage = CreateConVar("sm_carnage_knife_dmg", "0", "Enable or Disable knife damage in carnage round.");
	g_AutoBhop = CreateConVar("sm_carnage_autobhop", "1", "Enable or Disable autobhop in carnage round.");
	g_CommandName = CreateConVar("sm_carnage_command", "carnage,crng", "Command name(s). According to default values: !carnage/!crng = shows roundleft for carnage round and !fcarnage/!crng = forces carnage round.");
	
	HookConVarChange(g_SongPath, OnSettingsChanged);
	HookConVarChange(g_SongVolume, OnSettingsChanged);
	HookConVarChange(g_Prefix, OnSettingsChanged);
	HookConVarChange(g_KnifeDamage, OnSettingsChanged);
	HookConVarChange(g_AutoBhop, OnSettingsChanged);
	HookConVarChange(g_CommandName, OnSettingsChanged);
	
	AutoExecConfig(true, "carnage-mod");
	LoadTranslations("carnage_mod.phrases");
	
	for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i, false))
	{
		SDKHook(i, SDKHook_PreThink, PreThink);
		SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
		OnClientCookiesCached(i);
	}
}

public int OnSettingsChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(oldValue, newValue, true))
        return;
	if(convar == g_SongPath)
	{
		char buffer[100];
		GetConVarString(g_SongPath, gs_SongPath, sizeof(gs_SongPath));
		if (!StrEqual(gs_SongPath, "", false))
		{
			songsfound = ExplodeString(gs_SongPath, ",", CarnageSong, 6, 256);
			
			for (int i = 0; i <= songsfound -1; i++)
			{
				PrecacheSound(CarnageSong[i]);
				Format(buffer, 256, "sound/%s", CarnageSong[i]);
				ReplaceString(buffer, sizeof(buffer), " ", "");
				AddFileToDownloadsTable(buffer);
			}
		}
	}
	else if(convar == g_SongVolume)
	{
		g_fVolume = StringToFloat(newValue);
	}
	else if(convar == g_Prefix)
	{
		strcopy(Prefix, sizeof(Prefix), newValue);
	}
	else if(convar == g_KnifeDamage)
	{
		g_bKnifeDamage = !!StringToInt(newValue);
	}
	else if(convar == g_AutoBhop)
	{
		if(g_NoScope && StrEqual(newValue, "1", false))
		{
			SetHudTextParams(0.45, 0.350,  6.0, 0, 255, 0, 255, 0, 0.25, 0.5, 0.3);
			SetConVarBool(FindConVar("sv_autobunnyhopping"), true);
			for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i))
			{
				ShowHudText(i, -1, "AUTO-BHOP is turned ON");
			}
			
		}
		else if(g_NoScope && StrEqual(newValue, "0", false))
		{
			SetHudTextParams(0.45, 0.350, 6.0, 255, 0, 0, 255, 0, 0.25, 0.5, 0.3);
			
			SetConVarBool(FindConVar("sv_autobunnyhopping"), false);
			for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i))
			{
				ShowHudText(i, -1, "AUTO-BHOP is turned OFF");
			}
		}
		else
		{
			SetConVarBool(FindConVar("sv_autobunnyhopping"), !!StringToInt(newValue));
		}
	}
	else if(convar == g_CommandName)
	{
		int commandsfound = 0;
		char CommandName[32], Command[6][256], buffer[100];
		
		GetConVarString(g_CommandName, CommandName, sizeof(CommandName));
		commandsfound = ExplodeString(CommandName, ",", Command, 6, 256);
		for(int i = 0; i <= commandsfound -1; i++)
		{
			Format(buffer, 256, "sm_%s", Command[i]);
			RegConsoleCmd(buffer, CMD_CARNAGE);
			Format(buffer, 256, "sm_f%s", Command[i]);
			RegConsoleCmd(buffer, CMD_FCARNAGE);
			Format(buffer, 256, "sm_force%s", Command[i]);
			RegConsoleCmd(buffer, CMD_FCARNAGE);
		}
	}
}

public void OnConfigsExecuted()
{
	int commandsfound = 0;
	char CommandName[32], Command[6][256], buffer[100];
	
	GetConVarString(g_CommandName, CommandName, sizeof(CommandName));
	commandsfound = ExplodeString(CommandName, ",", Command, 6, 256);
	for(int i = 0; i <= commandsfound -1; i++)
	{
		Format(buffer, 256, "sm_%s", Command[i]);
		RegConsoleCmd(buffer, CMD_CARNAGE);
		Format(buffer, 256, "sm_f%s", Command[i]);
		RegConsoleCmd(buffer, CMD_FCARNAGE);
		Format(buffer, 256, "sm_force%s", Command[i]);
		RegConsoleCmd(buffer, CMD_FCARNAGE);
	}

	g_fVolume = GetConVarFloat(g_SongVolume);
	GetConVarString(g_Prefix, Prefix, sizeof(Prefix));
	g_bKnifeDamage = GetConVarBool(g_KnifeDamage);

	GetConVarString(g_SongPath, gs_SongPath, sizeof(gs_SongPath));
	if (!StrEqual(gs_SongPath, "", false))
	{
		songsfound = ExplodeString(gs_SongPath, ",", CarnageSong, 6, 256);
		
		for (int i = 0; i <= songsfound -1; i++)
		{
			PrecacheSound(CarnageSong[i]);
			Format(buffer, 256, "sound/%s", CarnageSong[i]);
			ReplaceString(buffer, sizeof(buffer), " ", "");
			AddFileToDownloadsTable(buffer);
		}
	}
}

public void OnMapStart()
{
	g_Round = 0;
	g_NoScope = false;
}

public void OnClientPutInServer(int client)
{
	OnClientCookiesCached(client);
	SDKHook(client, SDKHook_PreThink, PreThink);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

public void OnClientCookiesCached(int client)
{
	char sValue[8];
	GetClientCookie(client, Handle_BSM, sValue, sizeof(sValue));
	if(StrEqual(sValue, "") || StrEqual(sValue, "0"))
		bsm[client] = false;
	else
		bsm[client] = true;
}

public Action PreThink(int client)
{
	if(IsPlayerAlive(client))
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if(!IsValidEdict(weapon) || !IsValidEntity(weapon))
			return Plugin_Continue;

		char item[64];
		GetEdictClassname(weapon, item, sizeof(item)); 
		if(g_NoScope && IsNoScopeWeapon(item))
		{
			SetEntDataFloat(weapon, m_flNextSecondaryAttack, GetGameTime() + 9999.9); //Disable Scope
		}
	}
	return Plugin_Continue;
}

public Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if (!IsValidEntity(weapon) || !g_NoScope || g_bKnifeDamage)
		return Plugin_Continue;
	if (attacker <= 0 || attacker > MaxClients)
		return Plugin_Continue;
	char WeaponName[20];
	GetEntityClassname(weapon, WeaponName, sizeof(WeaponName));
	if(StrContains(WeaponName, "knife", false) != -1 || StrContains(WeaponName, "bayonet", false) != -1 || StrContains(WeaponName, "fists", false) != -1 || StrContains(WeaponName, "axe", false) != -1 || StrContains(WeaponName, "hammer", false) != -1 || StrContains(WeaponName, "spanner", false) != -1 || StrContains(WeaponName, "melee", false) != -1)
	{
		PrintCenterText(attacker, "Knife damage is disabled in this round.");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnRoundEnd(Event hEvent, const char[] sName, bool dontBroadcast)
{
	if(g_NoScope)
	{
		g_NoScope = false;
		GameRules_SetProp("m_bTCantBuy", false, _, _, true);
		GameRules_SetProp("m_bCTCantBuy", false, _, _, true);
		CreateTimer(GetConVarFloat(FindConVar("mp_round_restart_delay"))-0.1, Weapon_Strip);
		if(g_AutoBhop.BoolValue)
		{
			SetHudTextParams(0.45, 0.350, 6.0, 255, 0, 0, 255, 0, 0.25, 0.5, 0.3);
			SetConVarBool(FindConVar("sv_autobunnyhopping"), false);
			for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i))
			{
				ShowHudText(i, -1, "AUTO-BHOP is turned OFF");
			}
		}
		strcopy(song, sizeof(song), "");
	}
}

public void OnRoundStart(Event hEvent, const char[] sName, bool dontBroadcast)
{
	if (!IsWarmup()) 
	{ 
		g_Round++;
		if (g_Round == g_EveryWhichRound.IntValue)
		{
			CreateTimer(1.0, Start_Carnage);
		}
		else
		{
			int g_RestaRound = g_EveryWhichRound.IntValue - g_Round;
			if(g_RestaRound == 1) CPrintToChatAll("%t", "Round", Prefix, g_RestaRound);
			else CPrintToChatAll("%t", "Rounds", Prefix, g_RestaRound);
		}
	}
}

public Action CMD_FCARNAGE(int client, int args)
{
	if(g_NoScope)
	{
		CPrintToChat(client, "%t", "AlreadyCarn", Prefix);
		return Plugin_Handled;
	}
	GetFlags(client);
	if(g_bForceCarnage[client])
	{
		CreateTimer(1.0, Start_Carnage);
	}
	else
	{
		CPrintToChat(client, "%t", "Admin", Prefix);
	}
	return Plugin_Handled;
}

public Action CMD_CARNAGE(int client, int args)
{
	if (g_NoScope)
	{
		CPrintToChat(client, "%t", "ThisIsCarn", Prefix);
	}
	else
	{ 
		int g_RestaRound = g_EveryWhichRound.IntValue - g_Round;
		if(g_RestaRound == 1) CPrintToChatAll("%t", "Round", Prefix, g_RestaRound);
		else CPrintToChatAll("%t", "Rounds", Prefix, g_RestaRound);
	}
	return Plugin_Handled;
}

public Action CMD_BSM(int client, int args)
{
	if(!bsm[client])
	{
		SetClientCookie(client, Handle_BSM, "1");
		bsm[client] = true;
	}
	else
	{
		SetClientCookie(client, Handle_BSM, "0");
		bsm[client] = false;
	}
	char OFF[16], ON[16];
	Format(OFF, sizeof(OFF), "%t", "Off");
	Format(ON, sizeof(ON), "%t", "On");
	CPrintToChat(client, "%t", "BSM", Prefix, bsm[client] ?  OFF : ON);
	return Plugin_Handled;
}

public Action Start_Carnage(Handle timer)
{
	g_NoScope = true;
	g_Round = 0;
	GameRules_SetProp("m_bTCantBuy", true, _, _, true);
	GameRules_SetProp("m_bCTCantBuy", true, _, _, true);
	CPrintToChatAll("%t", "ThisIsCarn", Prefix);
	CPrintToChatAll("%t", "ThisIsCarn", Prefix);
	CPrintToChatAll("%t", "ThisIsCarn", Prefix);
	DoWeapons();
	if(g_AutoBhop.BoolValue)
	{
		SetHudTextParams(0.45, 0.350,  6.0, 0, 255, 0, 255, 0, 0.25, 0.5, 0.3);
		SetConVarBool(FindConVar("sv_autobunnyhopping"), true);
		for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i))
		{
			ShowHudText(i, -1, "AUTO-BHOP is turned ON");
		}
	}
	if(songsfound > 0)
	{
		if (songsfound < 2)
		{
			StrCat(song, sizeof(song), CarnageSong[randomsong]);
		}
		else
		{
			randomsong = GetRandomInt(0, songsfound - 1);
			StrCat(song, sizeof(song), CarnageSong[randomsong]);
		}
	}
	for(int client = 1; client <= MaxClients; client++)
	{
		if (IsValidClient(client))
		{	
			if(!bsm[client])
			{
				EmitSoundToClient(client, song, _, _, _, _, g_fVolume);
			}
			else
			{
				CPrintToChat(client, "%t", "TurnOnBsm", Prefix, song);
			}
		}
	}
	timer = null;
	return Plugin_Stop;
}

public Action Weapon_Strip(Handle timer)
{
	for(int client = 1; client <= MaxClients; client++) if(IsValidClient(client, false))
	{
		Client_RemoveAllWeapons(client, "weapon_knife");
	}
	timer = null;
	return Plugin_Stop;
}

void DoWeapons()
{
	for(int client = 1; client <= MaxClients; client++) if(IsValidClient(client, false))
	{
		Client_RemoveAllWeapons(client, "weapon_knife");
	}
	CreateTimer(0.1, TIMER_AWP);
}

public Action TIMER_AWP(Handle timer)
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if (IsValidClient(client, false) && IsPlayerAlive(client))
		{
			Client_GiveWeaponAndAmmo(client, "weapon_awp", _, 100, _, 200);
			CPrintToChat(client, "%t", "AWP", Prefix);
		}
	}
	timer = null;
	return Plugin_Stop;
}

bool IsNoScopeWeapon(char[] weapon)
{
	if(StrEqual(weapon, "weapon_scout")
		|| StrEqual(weapon, "weapon_g3sg1")
		|| StrEqual(weapon, "weapon_ssg08")
		|| StrEqual(weapon, "weapon_aug")
		|| StrEqual(weapon, "weapon_sg556")
		|| StrEqual(weapon, "weapon_awp")
		|| StrEqual(weapon, "weapon_scar20"))
		return true;
	return false;
}

public void GetFlags(int client)
{
	if (IsClientInGame(client))
	{
		char flag[8];
		int g_hFlag;
		GetConVarString(g_ADMINFLAG, flag, sizeof(flag));
		if (StrEqual(flag, "a")) g_hFlag = ADMFLAG_RESERVATION;
		else if (StrEqual(flag, "b")) g_hFlag = ADMFLAG_GENERIC;
		else if (StrEqual(flag, "c")) g_hFlag = ADMFLAG_KICK;
		else if (StrEqual(flag, "d")) g_hFlag = ADMFLAG_BAN;
		else if (StrEqual(flag, "e")) g_hFlag = ADMFLAG_UNBAN;
		else if (StrEqual(flag, "f")) g_hFlag = ADMFLAG_SLAY;
		else if (StrEqual(flag, "g")) g_hFlag = ADMFLAG_CHANGEMAP;
		else if (StrEqual(flag, "h")) g_hFlag = ADMFLAG_CONVARS;
		else if (StrEqual(flag, "i")) g_hFlag = ADMFLAG_CONFIG;
		else if (StrEqual(flag, "j")) g_hFlag = ADMFLAG_CHAT;
		else if (StrEqual(flag, "k")) g_hFlag = ADMFLAG_VOTE;
		else if (StrEqual(flag, "l")) g_hFlag = ADMFLAG_PASSWORD;
		else if (StrEqual(flag, "m")) g_hFlag = ADMFLAG_RCON;
		else if (StrEqual(flag, "n")) g_hFlag = ADMFLAG_CHEATS;
		else if (StrEqual(flag, "z")) g_hFlag = ADMFLAG_ROOT;
		else if (StrEqual(flag, "o")) g_hFlag = ADMFLAG_CUSTOM1;
		else if (StrEqual(flag, "p")) g_hFlag = ADMFLAG_CUSTOM2;
		else if (StrEqual(flag, "q")) g_hFlag = ADMFLAG_CUSTOM3;
		else if (StrEqual(flag, "r")) g_hFlag = ADMFLAG_CUSTOM4;
		else if (StrEqual(flag, "s")) g_hFlag = ADMFLAG_CUSTOM5;
		else if (StrEqual(flag, "t")) g_hFlag = ADMFLAG_CUSTOM6;
		else
		{
			SetFailState("The given flag in sm_carnage_flag is invalid");
		}
		
		int flags = GetUserFlagBits(client);		
		if (flags & g_hFlag)
		{
			g_bForceCarnage[client] = true;
		}
		else
		{
			g_bForceCarnage[client] = false;
		}
	}
}

stock bool IsWarmup() 
{ 
    int warmup = GameRules_GetProp("m_bWarmupPeriod", 4, 0); 
    if (warmup == 1) return true; 
    else return false; 
}

bool IsValidClient(int client, bool botz = true)
{ 
    if (!(1 <= client <= MaxClients) || !IsClientInGame(client) || !IsClientConnected(client) || botz && IsFakeClient(client) || IsClientSourceTV(client)) 
        return false; 
     
    return true;
}
