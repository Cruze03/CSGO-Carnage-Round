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
bool g_NoScope = false, g_bKnifeDamage = false, g_bCSGO = false;
char Prefix[100];
bool GotWeapon[MAXPLAYERS+1] = false;

//Song Path Variables
char gs_SongPath[256];
char CarnageSong[6][256];
int songsfound = 0;
char song[64];
int randomsong = 0;
float g_fVolume = 0.05;

//Cvars
ConVar g_EveryWhichRound, g_SongPath, g_SongVolume, g_Prefix, g_KnifeDamage, g_AutoBhop, g_CommandName, g_StripWeapon, g_StripWeaponMethod;

//ClientPrefs
Handle Handle_BSM;
bool bsm[MAXPLAYERS+1];

//Advert
Handle g_Advert;

public Plugin myinfo = 
{
	name = "[CSS/CSGO] Carnage Round", 
	author = "Elitcky, Cruze",
	description = "Noscope Rounds every X rounds.",
	version = "1.5.3",
	url = "http://steamcommunity.com/id/stormsmurf2 ; http://steamcommunity.com/profiles/76561198132924835"
};

public void OnPluginStart()
{
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_end", OnRoundEnd);

	RegConsoleCmd("sm_bsm", CMD_BSM);
	RegConsoleCmd("sm_awp", CMD_AWP);
	RegConsoleCmd("sm_scout", CMD_SCOUT);
	
	Handle_BSM = RegClientCookie("Bhop Sound Mute", "Sound setting", CookieAccess_Private);

	g_EveryWhichRound = CreateConVar("sm_carnage_round", "5", "Interval between carnage rounds.");
	g_SongPath = CreateConVar("sm_carnage_song", "misc/carnageround/ronda_carnageR.mp3,misc/carnageround/ronda_carnage2R.mp3", "DON'T USE SPACE BETWEEN \",\"");
	g_SongVolume = CreateConVar("sm_carnage_song_volume", "0.05", "Volume of song(s).");
	g_Prefix = CreateConVar("sm_carnage_prefix", "{green}[CARNAGE]{default}", "Change plugin's prefix of chat messages.");
	g_KnifeDamage = CreateConVar("sm_carnage_knife_dmg", "0", "Enable or Disable knife damage in carnage round.");
	g_AutoBhop = CreateConVar("sm_carnage_autobhop", "1", "Enable or Disable autobhop in carnage round.");
	g_CommandName = CreateConVar("sm_carnage_command", "carnage,crng", "Command name(s). According to default values: !carnage/!crng = shows roundleft for carnage round and !fcarnage/!crng = forces carnage round.");
	g_StripWeapon = CreateConVar("sm_carnage_stripwpn_atrndend", "1", "Strip all weapons but knife at roundend? 0 to disable.");
	g_StripWeaponMethod = CreateConVar("sm_carnage_stripwpn_method", "0", "Strip all weapons method? 0 = SMLIB Method. 1 = advanced admin method. [Added this because my friend reported me crash issue if using SMLIB Method. Use \"1\" if you are facing the same!]");
	
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
		SDKHook(i, SDKHook_WeaponDrop, OnWeaponDrop);
		OnClientCookiesCached(i);
	}
	
	g_bCSGO = GetEngineVersion() == Engine_CSGO ? true : false;
	
	if(GetEngineVersion() != Engine_CSGO && GetEngineVersion() != Engine_CSS)
	{
		SetFailState("[CARNAGE] This plugin is supported in CSGO and CSS only.");
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
				ShowHudText(i, -1, "%t", "ABON");
			}
			
		}
		else if(g_NoScope && StrEqual(newValue, "0", false))
		{
			SetHudTextParams(0.45, 0.350, 6.0, 255, 0, 0, 255, 0, 0.25, 0.5, 0.3);
			
			SetConVarBool(FindConVar("sv_autobunnyhopping"), false);
			for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i))
			{
				ShowHudText(i, -1, "%t", "ABOFF");
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
			RegAdminCmd(buffer, CMD_FCARNAGE, ADMFLAG_RCON);
			Format(buffer, 256, "sm_force%s", Command[i]);
			RegAdminCmd(buffer, CMD_FCARNAGE, ADMFLAG_RCON);
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
	GameRules_SetProp("m_bTCantBuy", false, _, _, true);
	GameRules_SetProp("m_bCTCantBuy", false, _, _, true);
	strcopy(song, sizeof(song), "");
	if(g_Advert != null)
	{
		KillTimer(g_Advert);
		g_Advert = null;
	}
}

public void OnClientPutInServer(int client)
{
	OnClientCookiesCached(client);
	SDKHook(client, SDKHook_PreThink, PreThink);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
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
			if(!GotWeapon[client])
				GotWeapon[client] = true;
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
		PrintCenterText(attacker, "%t", "KnifeDmg");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnWeaponDrop(int client, int weapon)
{
	if(g_NoScope)
	{
		CPrintToChat(client, "%t", "WeaponDrop", Prefix);
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
				ShowHudText(i, -1, "%t", "ABOFF");
				GotWeapon[i] = false;
			}
		}
		strcopy(song, sizeof(song), "");
		if(g_Advert != null)
		{
			KillTimer(g_Advert);
			g_Advert = null;
		}
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
	CreateTimer(1.0, Start_Carnage);
	return Plugin_Handled;
}

public Action CMD_CARNAGE(int client, int args)
{
	if (g_NoScope)
	{
		CPrintToChat(client, "%s %t", Prefix, "ThisIsCarn");
	}
	else
	{ 
		int g_RestaRound = g_EveryWhichRound.IntValue - g_Round;
		if(g_RestaRound == 1) CPrintToChatAll("%t", "Round", Prefix, g_RestaRound);
		else CPrintToChatAll("%t", "Rounds", Prefix, g_RestaRound);
	}
	return Plugin_Handled;
}

public Action CMD_AWP(int client, int args)
{
	if(!g_NoScope)
	{
		CPrintToChat(client, "%t", "UseThisInCarn", Prefix);
		return Plugin_Handled;
	}
	if(GotWeapon[client])
	{
		CPrintToChat(client, "%t", "ALREADYWEAPON", Prefix);
		return Plugin_Handled;
	}
	else
	{
		Client_GiveWeaponAndAmmo(client, "weapon_awp", _, 100, _, 200);
		CPrintToChat(client, "%t", "AWP", Prefix);
		GotWeapon[client] = true;
	}
	return Plugin_Handled;
}

public Action CMD_SCOUT(int client, int args)
{
	if(!g_NoScope)
	{
		CPrintToChat(client, "%t", "UseThisInCarn", Prefix);
		return Plugin_Handled;
	}
	if(GotWeapon[client])
	{
		CPrintToChat(client, "%t", "ALREADYWEAPON", Prefix);
		return Plugin_Handled;
	}
	else
	{
		if(g_bCSGO)
			Client_GiveWeaponAndAmmo(client, "weapon_ssg08", _, 100, _, 200);
		else
			Client_GiveWeaponAndAmmo(client, "weapon_scout", _, 100, _, 200);
		CPrintToChat(client, "%t", "SCOUT", Prefix);
		GotWeapon[client] = true;
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
	GameRules_SetProp("m_bTCantBuy", true, _, _, true);
	GameRules_SetProp("m_bCTCantBuy", true, _, _, true);
	ClearMap();
	DoWeapons();
	SetHudTextParams(0.45, 0.30,  6.0, 0, 200, 200, 255, 0, 0.25, 0.5, 0.3);
	for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i))
	{
		ShowHudText(i, -1, "%t", "ThisIsCarn");
	}
	g_NoScope = true;
	g_Round = 0;
	CPrintToChatAll("%s %t", Prefix, "ThisIsCarn");
	CPrintToChatAll("%s %t", Prefix, "ThisIsCarn");
	CPrintToChatAll("%s %t", Prefix, "ThisIsCarn");
	if(g_AutoBhop.BoolValue)
	{
		SetHudTextParams(-1.0, 1.0,  6.0, 0, 255, 0, 255, 0, 0.25, 0.5, 0.3);
		SetConVarBool(FindConVar("sv_autobunnyhopping"), true);
		for(int i = 1; i <= MaxClients; i++) if(IsValidClient(i))
		{
			ShowHudText(i, -1, "%t", "ABON");
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
	g_Advert = CreateTimer(6.0, Advert, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	timer = null;
	return Plugin_Stop;
}

void ClearMap()
{
	char buffer[64];
	for(char entity = MaxClients; entity < GetMaxEntities(); entity++)
	{
		if(IsValidEntity(entity))
		{
			GetEntityClassname(entity, buffer, sizeof(buffer));
			if(((StrContains(buffer, "weapon_", false) != -1) && (GetEntProp(entity, Prop_Data, "m_iState") == 0) && (GetEntProp(entity, Prop_Data, "m_spawnflags") != 1)) || StrEqual(buffer, "item_defuser", false) && (GetEntPropEnt(entity, Prop_Send, "m_leader") == -1))
			{
				AcceptEntityInput(entity, "Kill");
			}
		}
	}
}

void DoWeapons()
{
	for(int client = 1; client <= MaxClients; client++) if(IsValidClient(client, false) && IsPlayerAlive(client))
	{
		if(g_StripWeaponMethod.BoolValue)
		{
			for(int i = 0; i < 5; i++)
			{
				char weapon = -1;
				while((weapon = GetPlayerWeaponSlot(client, i)) != -1)
				{
					if(IsValidEntity(weapon))
					{
						RemovePlayerItem(client, weapon);
					}
				}
			}
			SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
			SetEntProp(client, Prop_Send, "m_bHasHeavyArmor", 0);
			SetEntProp(client, Prop_Send, "m_ArmorValue", 0);
			SetEntProp(client, Prop_Send, "m_bHasHelmet", 0);
			CreateTimer(0.1, GiveKnifePls);
		}
		else
		{
			Client_RemoveAllWeapons(client, "weapon_knife");
		}
		Menu menu = new Menu(WeaponHandler);
		menu.SetTitle("Choose your weapon");
		menu.AddItem("awp", "AWP");
		menu.AddItem("scout", "Scout");
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public Action Advert(Handle timer)
{
	for(int client = 1; client <= MaxClients; client++) if(IsValidClient(client, false) && IsPlayerAlive(client))
	{
		if(g_NoScope && !GotWeapon[client])
		{
			CPrintToChat(client, "%t", "ADVERT", Prefix);
		}
	}
	return Plugin_Continue;
}

public Action GiveKnifePls(Handle timer)
{
	for(int client = 1; client <= MaxClients; client++) if(IsValidClient(client, false) && IsPlayerAlive(client))
	{
		GivePlayerItem(client, "weapon_knife");
	}
	timer = null;
	return Plugin_Stop;
}

public int WeaponHandler(Menu menu, MenuAction action, int client, int item) 
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
	else if(action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(item, info, sizeof(info));
		if(StrEqual(info, "awp"))
		{
			if(!GotWeapon[client])
			{
				Client_GiveWeaponAndAmmo(client, "weapon_awp", _, 100, _, 200);
				CPrintToChat(client, "%t", "AWP", Prefix);
				GotWeapon[client] = true;
			}
			else
			{
				CPrintToChat(client, "%t", "ALREADYWEAPON", Prefix);
			}
		}
		else if(StrEqual(info, "scout"))
		{
			if(!GotWeapon[client])
			{	
				if(g_bCSGO)
					Client_GiveWeaponAndAmmo(client, "weapon_ssg08", _, 100, _, 200);
				else
					Client_GiveWeaponAndAmmo(client, "weapon_scout", _, 100, _, 200);
				CPrintToChat(client, "%t", "SCOUT", Prefix);
				GotWeapon[client] = true;
			}
			else
			{
				CPrintToChat(client, "%t", "ALREADYWEAPON", Prefix);
			}
		}
	}
}

public Action Weapon_Strip(Handle timer)
{
	for(int client = 1; client <= MaxClients; client++) if(IsValidClient(client, false) && g_StripWeapon.BoolValue)
	{
		if(!g_StripWeaponMethod.BoolValue)
		{
			Client_RemoveAllWeapons(client, "weapon_knife");
		}
		else
		{
			for(int i = 0; i < 5; i++)
			{
				char weapon = -1;
				while((weapon = GetPlayerWeaponSlot(client, i)) != -1)
				{
					if(IsValidEntity(weapon))
					{
						RemovePlayerItem(client, weapon);
					}
				}
			}
			SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
			SetEntProp(client, Prop_Send, "m_bHasHeavyArmor", 0);
			SetEntProp(client, Prop_Send, "m_ArmorValue", 0);
			SetEntProp(client, Prop_Send, "m_bHasHelmet", 0);
		}
	}
	timer = null;
	return Plugin_Stop;
}

bool IsNoScopeWeapon(char[] weapon)
{
	if(StrEqual(weapon, "weapon_scout")
		|| StrEqual(weapon, "weapon_ssg08")
		|| StrEqual(weapon, "weapon_awp"))
		return true;
	return false;
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
