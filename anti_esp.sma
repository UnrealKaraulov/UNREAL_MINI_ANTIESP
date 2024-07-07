#include <amxmodx>
#include <reapi>
#include <fakemeta>
#include <engine>
#include <xs>

#include <easy_cfg>


#pragma ctrlchar '\'

new PLUGIN_NAME[] = "UNREAL ANTI-ESP";
new PLUGIN_VERSION[] = "3.5";
new PLUGIN_AUTHOR[] = "Karaulov";


#define GROUP_OP_AND  0
#define GROUP_OP_NAND 1
#define GROUP_OP_IGNORE 2

#define MAX_CHANNEL CHAN_STREAM
new g_iChannelReplacement[MAX_PLAYERS + 1][MAX_CHANNEL + 1];

new g_sSoundClassname[64] = "info_target";
new g_sFakePath[64] = "player/pl_step5.wav";

new bool:g_bPlayerConnected[MAX_PLAYERS + 1] = {false,...};
new bool:g_bPlayerBot[MAX_PLAYERS + 1] = {false,...};
new bool:g_bRepeatChannelMode = false;
new bool:g_bGiveSomeRandom = false;
new bool:g_bReinstallNewSounds = false;
new bool:g_bReplaceSoundForAll = false;
new bool:g_bAntiespForBots = true;
new bool:g_bCrackOldEspBox = true;
new bool:g_bVolumeRangeBased = true;
new bool:g_bUseOriginalSounds = false;
new bool:g_bDebugDumpAllSounds = false;

new g_iCurEnt = 0;
new g_iCurChannel = 0;
new g_iFakeEnt = 0;
new g_iReplaceSounds = 0;
new g_iMaxEntsForSounds = 13;
new g_iHideEventsMode = 0;
new g_iFakeSoundMode = 1;
new g_iProtectStatus = 0;

/* from engine constants */
#define SOUND_NOMINAL_CLIP_DIST 1000.0

new Float:g_fMaxSoundDist = SOUND_NOMINAL_CLIP_DIST;
new Float:g_fRangeBasedDist = 64.0;
new Float:g_fMinSoundVolume = 0.006;

new Float:g_fFakeTime = 0.0;

new Array:g_aPrecachedSounds;
new Array:g_aOriginalSounds;
new Array:g_aReplacedSounds;
new Array:g_aSoundEnts;

new const g_sGunsEvents[][] = {
    "events/ak47.sc", "events/aug.sc", "events/awp.sc", "events/deagle.sc", 
    "events/elite_left.sc", "events/elite_right.sc", "events/famas.sc", 
    "events/fiveseven.sc", "events/g3sg1.sc", "events/galil.sc", "events/glock18.sc", 
    "events/mac10.sc", "events/m249.sc", "events/m3.sc", "events/m4a1.sc", 
    "events/mp5n.sc", "events/p228.sc", "events/p90.sc", "events/scout.sc", 
    "events/sg550.sc", "events/sg552.sc", "events/tmp.sc", "events/ump45.sc", 
    "events/usp.sc", "events/xm1014.sc"
};

new const g_sGunsSounds[][][] = {
    {"weapons/ak47-1.wav", "weapons/ak47-1.wav"},
    {"weapons/aug-1.wav", "weapons/aug-1.wav"},
    {"weapons/awp1.wav", "weapons/awp1-1.wav"},
    {"weapons/deagle-1.wav", "weapons/deagle-1.wav"},
    {"weapons/elite_fire.wav", "weapons/elite_fire-1.wav"},
    {"weapons/elite_fire.wav", "weapons/elite_fire-1.wav"},
    {"weapons/famas-1.wav", "weapons/famas-1.wav"},
    {"weapons/fiveseven-1.wav", "weapons/fiveseven-1.wav"},
    {"weapons/g3sg1-1.wav", "weapons/g3sg1-1.wav"},
    {"weapons/galil-1.wav", "weapons/galil-1.wav"},
    {"weapons/glock18-2.wav", "weapons/glock18-2.wav"},
    {"weapons/mac10-1.wav", "weapons/mac10-1.wav"},
    {"weapons/m249-1.wav", "weapons/m249-1.wav"},
    {"weapons/m3-1.wav", "weapons/m3-1.wav"},
	{"weapons/m4a1-1.wav", "weapons/m4a1_unsil-1.wav"},
	{"weapons/mp5-1.wav", "weapons/mp5-1.wav"},
	{"weapons/p228-1.wav","weapons/p228-1.wav"},
	{"weapons/p90-1.wav","weapons/p90-1.wav"},
	{"weapons/scout_fire-1.wav","weapons/scout_fire-1.wav"},
	{"weapons/sg550-1.wav","weapons/sg550-1.wav"},
	{"weapons/sg552-1.wav","weapons/sg552-1.wav"},
	{"weapons/tmp-1.wav","weapons/tmp-1.wav"},
	{"weapons/ump45-1.wav","weapons/ump45-1.wav"},
	{"weapons/usp1.wav","weapons/usp_unsil-1.wav"},
	{"weapons/xm1014-1.wav","weapons/xm1014-1.wav"}
};

new g_iEventIdx[sizeof(g_sGunsEvents)] = {0,...};

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	create_cvar("unreal_no_esp", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY);

	g_iFakeEnt = rg_create_entity("info_target");
	if (!g_iFakeEnt)
	{
		set_fail_state("Can't create fake entity");
		return;
	}
	set_entvar(g_iFakeEnt,var_classname, g_sSoundClassname);

	new iFirstSndEnt = rg_create_entity("info_target");
	if (!iFirstSndEnt)
	{
		set_fail_state("Can't create sound entity");
		return;
	}
	set_entvar(iFirstSndEnt,var_classname, g_sSoundClassname);

	ArrayPushCell(g_aSoundEnts, iFirstSndEnt);

	RegisterHookChain(RG_CBasePlayer_Spawn, "RG_CBasePlayer_Spawn_post", true);
	RegisterHookChain(RH_SV_StartSound, "RH_SV_StartSound_pre", false);
	
	for (new i = 0; i <= MAX_PLAYERS; i++) 
	{
		for (new j = 0; j < MAX_CHANNEL; j++) 
		{
			g_iChannelReplacement[i][j] = 0;
		}
	}
}

new bool:one_time_channel_warn = true;

public fill_entity_and_channel(id, channel)
{
	if (channel > MAX_CHANNEL || channel <= 0)
		return 0;

	if (!g_bRepeatChannelMode)
	{
		if (g_iChannelReplacement[id][channel] != 0)
			return g_iChannelReplacement[id][channel];
	}	
	
	g_iCurChannel++;
	if (g_iCurChannel > MAX_CHANNEL)
	{
		g_iCurChannel = 1;
		g_iCurEnt++;
		if (g_iCurEnt < g_iMaxEntsForSounds)
		{
			new iSndEnt = rg_create_entity("info_target");
			if (!iSndEnt)
			{
				set_fail_state("Can't create sound entity");
				return 0;
			}
			
			ArrayPushCell(g_aSoundEnts, iSndEnt);
			set_entvar(iSndEnt,var_classname, g_sSoundClassname);
		}
		else 
		{
			if (one_time_channel_warn && !g_bRepeatChannelMode)
			{
				one_time_channel_warn = false;
				log_amx("Too many sound entities, please increase g_iMaxEntsForSounds in unreal_anti_esp.cfg[this can fix not hearing sounds]\n");
			}
			g_iCurEnt = 0;
		}
	}

	g_iChannelReplacement[id][channel] = PackChannelEnt(g_iCurChannel,g_iCurEnt);
	return g_iChannelReplacement[id][channel];
}

public InitDefaultSoundArray()
{
	ArrayPushString(g_aOriginalSounds, "player/pl_step1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_step2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_step3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_step4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_dirt1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_dirt2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_dirt3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_dirt4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_duct1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_duct2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_duct3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_duct4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_grate1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_grate2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_grate3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_grate4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_metal1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_metal2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_metal3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_metal4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_ladder1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_ladder2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_ladder3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_ladder4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_slosh1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_slosh2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_slosh3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_slosh4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_snow1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_snow2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_snow3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_snow4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_snow5.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_snow6.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_swim1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_swim2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_swim3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_swim4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_tile1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_tile2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_tile3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_tile4.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_tile5.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_wade1.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_wade2.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_wade3.wav");
	ArrayPushString(g_aOriginalSounds, "player/pl_wade4.wav");

	new rnd_str[64];

	if (g_bReinstallNewSounds)
	{
		for(new i = 0; i < ArraySize(g_aOriginalSounds); i++)
		{
			RandomSoundPostfix("pl_shell/",rnd_str,charsmax(rnd_str));
			ArrayPushString(g_aReplacedSounds, rnd_str);
		}
	}
	else 
	{
		for(new i = 0; i < ArraySize(g_aOriginalSounds); i++)
		{
			StandSoundPostfix("pl_shell/",rnd_str,charsmax(rnd_str));
			ArrayPushString(g_aReplacedSounds, rnd_str);
		}
	}
}

public client_putinserver(id)
{
	new bool:isBot = is_user_bot(id) > 0;
	new bool:isHltv = is_user_hltv(id) > 0;

	if (isBot || isHltv)
	{
		g_bPlayerConnected[id] = false;
	}
	else 
	{
		g_bPlayerConnected[id] = true;
	}

	g_bPlayerBot[id] = isBot;
	
	if (task_exists(id))
	{
		remove_task(id);
	}
}

public client_disconnected(id)
{
	g_bPlayerConnected[id] = false;
	
	if (task_exists(id))
	{
		remove_task(id);
	}
}

public PrecacheEvent(type, const name[])
{
	for(new i = 0; i < sizeof(g_sGunsEvents); i++)
	{
		if(equal(g_sGunsEvents[i], name))
		{
			g_iEventIdx[i] = get_orig_retval();
		}
	}
}

public PrecacheSound(const szSound[])
{
	static tmpstr[64];

	new i = ArrayFindString(g_aOriginalSounds, szSound);
	if (i < 0)
	{
		return FMRES_IGNORED;
	}
	
	ArrayGetString(g_aReplacedSounds, i, tmpstr, charsmax(tmpstr));
	if (ArrayGetCell(g_aPrecachedSounds,i) <= 0)
	{
		set_fail_state("No sound/%s found!", tmpstr);
		return FMRES_IGNORED;
	}
	forward_return(FMV_CELL, tmpstr);
	return FMRES_SUPERCEDE;
}

public plugin_end()
{
	ArrayDestroy(g_aOriginalSounds);
	ArrayDestroy(g_aReplacedSounds);
	ArrayDestroy(g_aPrecachedSounds);
	ArrayDestroy(g_aSoundEnts);

	if (g_iProtectStatus == 1)
	{
		log_amx("Warning! Protection is not active, possible has conflict with another plugins!");
	}
}

public plugin_precache()
{
	cfg_set_path("/plugins/unreal_anti_esp.cfg");
	
	RandomString(g_sSoundClassname, 15);
	g_sSoundClassname[5] = '_';

	g_aOriginalSounds = ArrayCreate(64);
	g_aReplacedSounds = ArrayCreate(64);
	g_aPrecachedSounds = ArrayCreate();
	g_aSoundEnts = ArrayCreate();

	cfg_read_str("general","fake_path",g_sFakePath,g_sFakePath,charsmax(g_sFakePath));
	cfg_read_int("general","enable_fake_sounds", g_iFakeSoundMode, g_iFakeSoundMode);
	cfg_read_str("general","ent_classname",g_sSoundClassname,g_sSoundClassname,charsmax(g_sSoundClassname));
	cfg_read_int("general","max_ents_for_sounds", g_iMaxEntsForSounds, g_iMaxEntsForSounds);
	cfg_read_bool("general","repeat_channel_mode", g_bRepeatChannelMode, g_bRepeatChannelMode);
	cfg_read_bool("general","more_random_mode", g_bGiveSomeRandom, g_bGiveSomeRandom);
	cfg_read_bool("general","reinstall_with_new_sounds", g_bReinstallNewSounds, g_bReinstallNewSounds);
	cfg_read_bool("general","crack_old_esp_box", g_bCrackOldEspBox, g_bCrackOldEspBox);
	cfg_read_bool("general","volume_range_based", g_bVolumeRangeBased, g_bVolumeRangeBased);
	cfg_read_flt("general","volume_range_dist", g_fRangeBasedDist, g_fRangeBasedDist);
	cfg_read_flt("general","cut_off_sound_dist", g_fMaxSoundDist * 1.5, g_fMaxSoundDist);
	cfg_read_flt("general","cut_off_sound_vol", g_fMinSoundVolume, g_fMinSoundVolume);
	cfg_read_bool("general","replace_sound_for_all_ents", g_bReplaceSoundForAll, g_bReplaceSoundForAll);
	cfg_read_bool("general","antiesp_for_bots", g_bAntiespForBots, g_bAntiespForBots);
	cfg_read_int("general","hide_weapon_events", g_iHideEventsMode, g_iHideEventsMode);
	cfg_read_bool("general","USE_ORIGINAL_SOUND_PATHS", g_bUseOriginalSounds, g_bUseOriginalSounds);
	cfg_read_bool("general","DEBUG_DUMP_ALL_SOUNDS", g_bDebugDumpAllSounds, g_bDebugDumpAllSounds);

	static tmp_sound[64];
	static tmp_arg[64];

	if (!g_bUseOriginalSounds)
	{
		if (g_bReinstallNewSounds)
			cfg_write_bool("general","reinstall_with_new_sounds",false);
		cfg_read_int("sounds","sounds",g_iReplaceSounds,g_iReplaceSounds);


		if (g_iReplaceSounds == 0 || g_bReinstallNewSounds)
		{
			InitDefaultSoundArray();
			g_iReplaceSounds = ArraySize(g_aOriginalSounds);
			cfg_write_int("sounds","sounds",g_iReplaceSounds);
			
			if (!dir_exists("sound/pl_shell",true))
				mkdir("sound/pl_shell", _, true, "GAMECONFIG");
		}

		static tmp_sound_dest[64];
		for(new i = 0; i < g_iReplaceSounds; i++)
		{
			if (i < ArraySize(g_aOriginalSounds))
			{
				ArrayGetString(g_aOriginalSounds, i, tmp_sound, charsmax(tmp_sound));
				ArrayGetString(g_aReplacedSounds, i, tmp_sound_dest, charsmax(tmp_sound_dest));

				formatex(tmp_arg,charsmax(tmp_arg),"sound_%i_default", i + 1);
				cfg_write_str("sounds",tmp_arg,tmp_sound);
				formatex(tmp_arg,charsmax(tmp_arg),"sound_%i_replace", i + 1);
				cfg_write_str("sounds",tmp_arg,tmp_sound_dest);
			}
			else 
			{
				formatex(tmp_arg,charsmax(tmp_arg),"sound_%i_default", i + 1);
				cfg_read_str("sounds",tmp_arg,tmp_sound,tmp_sound,charsmax(tmp_sound));
				formatex(tmp_arg,charsmax(tmp_arg),"sound_%i_replace", i + 1);
				cfg_read_str("sounds",tmp_arg,tmp_sound_dest,tmp_sound_dest,charsmax(tmp_sound_dest));
			}
			ArrayPushString(g_aOriginalSounds,tmp_sound);
			ArrayPushString(g_aReplacedSounds,tmp_sound_dest);

			if (!sound_exists(tmp_sound_dest))
			{
				formatex(tmp_arg,charsmax(tmp_arg),"sound/%s",tmp_sound_dest);

				trim_to_dir(tmp_arg);
				if (!dir_exists(tmp_arg, true))
				{
					if (mkdir(tmp_arg, _, true, "GAMECONFIG") < 0)
					{
						set_fail_state("Fail while create %s dir",tmp_arg);
						return;
					}
				}
				
				formatex(tmp_arg,charsmax(tmp_arg),"sound/%s",tmp_sound);
				formatex(tmp_sound,charsmax(tmp_sound),"sound/%s",tmp_sound_dest);

				MoveSoundWithRandomTail(tmp_arg,tmp_sound);

				if (!sound_exists(tmp_sound_dest))
				{
					set_fail_state("Fail while move %s to %s",tmp_sound,tmp_sound_dest);
					return;
				}
			}
		}
	}

	if (!sound_exists(g_sFakePath))
	{
		formatex(tmp_sound,charsmax(tmp_sound),"sound/%s",g_sFakePath);
		CreateSilentWav(tmp_sound, random_float(0.1,0.25))
	}

	if (!sound_exists(g_sFakePath))
	{
		set_fail_state("No sound/%s found!",g_sFakePath);
		return;
	}
	
	for(new i = 0; i < ArraySize(g_aReplacedSounds);i++)
	{
		ArrayGetString(g_aReplacedSounds, i, tmp_arg, charsmax(tmp_arg));
		if (!sound_exists(tmp_arg))
		{
			set_fail_state("No sound/%s found!", tmp_arg);
			return;
		}
		ArrayPushCell(g_aPrecachedSounds, precache_sound(tmp_arg));
	}

	precache_sound(g_sFakePath);
	register_forward(FM_PrecacheSound, "PrecacheSound");

	if (g_iHideEventsMode > 0)
	{
		register_forward(FM_PrecacheEvent, "PrecacheEvent", true)
		register_forward(FM_PlaybackEvent, "FM_PlaybackEvent_pre", false);
	}
	
	log_amx("unreal_anti_esp loaded");
	log_amx("Settings:");
	log_amx(" g_sSoundClassname = %s (snd entity classname)", g_sSoundClassname);
	log_amx(" g_sFakePath = %s (fake sound path)", g_sFakePath);
	log_amx(" g_bRepeatChannelMode = %i (loop mode)", g_bRepeatChannelMode);
	log_amx(" g_bGiveSomeRandom = %i (adds more random to more protect)", g_bGiveSomeRandom);
	log_amx(" g_iReplaceSounds = %i (how many sounds to replace)", g_iReplaceSounds);
	log_amx(" g_bCrackOldEspBox = %i (cracks old esp box)", g_bCrackOldEspBox);
	log_amx(" g_bReplaceSoundForAll = %i (replaces sound for all ents)", g_bReplaceSoundForAll);
	log_amx(" g_bAntiespForBots = %i (enable antiesp for bots)", g_bAntiespForBots);
	log_amx(" g_bVolumeRangeBased = %i (uses volume based on distance)", g_bVolumeRangeBased);
	log_amx(" g_fRangeBasedDist = %f (distance for volume based mode)", g_fRangeBasedDist);
	log_amx(" g_fMaxSoundDist = %f (max sound hear distance)", g_fMaxSoundDist);
	log_amx(" g_fMinSoundVolume = %f (min sound hear volume)", g_fMinSoundVolume);
	log_amx(" g_bUseOriginalSounds = %i (use original sound paths)", g_bUseOriginalSounds);
	log_amx(" g_iHideEventsMode = %i (0 - disabled, 1 - emulate sound, 2 - full block)", g_iHideEventsMode);
	log_amx(" g_bDebugDumpAllSounds = %i (dumps all sounds debug/trace mode)", g_bDebugDumpAllSounds);
	log_amx(" g_iFakeSoundMode = %i (0 - disabled, 1 - fake sound, 2 - unreal fake sound)", g_iFakeSoundMode);

	if (g_bDebugDumpAllSounds)
	{
		log_amx("Warning! Dumping all sounds!");
	}

	if (g_bUseOriginalSounds)
	{
		log_amx("Warning! Using original sound paths! [No sound will be replaced]");
	}
}

rg_emit_sound_custom(entity, recipient, channel, const sample[], Float:vol = VOL_NORM, Float:attn = ATTN_NORM, flags = 0, pitch = PITCH_NORM, emitFlags = 0, 
					Float:vecSource[3] = {0.0,0.0,0.0}, bool:bForAll = false, iForceListener = 0)
{
	static Float:vecListener[3];
	
	for(new iListener = 1; iListener < MAX_PLAYERS + 1; iListener++)
	{
		if (g_bPlayerConnected[iListener] && (bForAll || iListener != recipient))
		{
			if (iForceListener > 0 && iListener != iForceListener)
				continue;

			get_entvar(iListener, var_origin, vecListener);

			static Float:direction[3];
			xs_vec_sub(vecSource, vecListener, direction);

			new Float:originalDistance = xs_vec_len(direction);
			xs_vec_normalize(direction, direction);

			if (originalDistance > g_fMaxSoundDist)
				continue;

			new Float:fSomeRandom = 0.0;
			if (g_bGiveSomeRandom)
			{
				fSomeRandom = random_float(0.0, g_fRangeBasedDist * 1.5) - g_fRangeBasedDist / 3.0;
			}

			if (!g_bVolumeRangeBased || originalDistance < g_fRangeBasedDist + fSomeRandom)
			{
				set_entvar(entity, var_origin, vecSource);
				if (channel == CHAN_STREAM)
					rh_emit_sound2(entity, iListener, channel, sample, vol, attn, SND_STOP, pitch, emitFlags, vecSource);
				rh_emit_sound2(entity, iListener, channel, sample, vol, attn, flags, pitch, emitFlags, vecSource);
				continue;
			}
			
			/* thanks s1lent for distance based sound volume calculation as in real client engine */
			static Float:vecFakeSound[3];

			xs_vec_mul_scalar(direction, g_fRangeBasedDist + fSomeRandom, vecFakeSound);
			xs_vec_add(vecListener, vecFakeSound, vecFakeSound);
			xs_vec_sub(vecFakeSound, vecListener, direction);

			new Float:dist_mult = attn / SOUND_NOMINAL_CLIP_DIST;
			new Float:flvol = vol;
			new Float:new_vol = flvol * (1.0 - (originalDistance * dist_mult)) / (1.0 - (xs_vec_len(direction) * dist_mult));

			/* bypass errors */
			if (new_vol > flvol)
				new_vol = flvol;
			if (new_vol <= 0)
				continue;
			
			set_entvar(entity, var_origin, vecFakeSound);
			if (channel == CHAN_STREAM)
				rh_emit_sound2(entity, iListener, channel, sample, new_vol, attn, SND_STOP, pitch, emitFlags, vecFakeSound);
			rh_emit_sound2(entity, iListener, channel, sample, new_vol, attn, flags, pitch, emitFlags, vecFakeSound);
		}
	}

	// hide fake ents coords
	vecListener[0] = random_float(-8190.0,8190.0);
	vecListener[1] = random_float(-8190.0,8190.0);
	vecListener[2] = random_float(-200.0,200.0);
	set_entvar(entity,var_origin,vecListener);
}

emit_fake_sound(Float:origin[3], Float:volume, Float:attenuation, fFlags, pitch, channel, iTargetPlayer = 0)
{
	if (iTargetPlayer > 0)
	{
		static Float:bakOrigin[3];
		if (random_num(0,100) > 50)
		{
			get_entvar(iTargetPlayer,var_origin,bakOrigin);
			set_entvar(iTargetPlayer,var_origin,origin);
			rh_emit_sound2(iTargetPlayer, iTargetPlayer, random_num(0,100) > 50 ? CHAN_VOICE : CHAN_STREAM, g_sFakePath, volume, attenuation, fFlags, pitch, 0, origin);
			set_entvar(iTargetPlayer,var_origin,bakOrigin);
		}
		else 
		{
			rh_emit_sound2(g_iFakeEnt, iTargetPlayer, channel, g_sFakePath, volume, attenuation, fFlags, pitch, 0, origin);
			set_entvar(g_iFakeEnt,var_origin,origin);
		}
	}
	else 
	{
		set_entvar(g_iFakeEnt,var_origin,origin);

		for(new i = 1; i < MAX_PLAYERS + 1; i++)
		{
			if (g_bPlayerConnected[i])
			{
				rh_emit_sound2(g_iFakeEnt, i, channel, g_sFakePath, volume, attenuation, fFlags, pitch, 0, origin);
			}
		}
	}
}

public RH_SV_StartSound_pre(const recipients, const entity, const channel, const sample[], const volume, Float:attenuation, const fFlags, const pitch)
{
	static tmp_sample[64];

	tmp_sample[0] = EOS;

	if (g_bDebugDumpAllSounds)
	{
		static tmp_section_name[256];

		static tmp_debug[256];

		get_mapname(tmp_debug,charsmax(tmp_debug));
		formatex(tmp_section_name,charsmax(tmp_section_name),"DEBUG_MAP_%s", tmp_debug);

		static tmp_debug2[256];
		
		formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_channel", entity);
		formatex(tmp_debug2,charsmax(tmp_debug2),"%i", channel);
		cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);

		formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_sample", entity);
		formatex(tmp_debug2,charsmax(tmp_debug2),"%s", sample);
		cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);

		formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_volume", entity);
		formatex(tmp_debug2,charsmax(tmp_debug2),"%f", volume / 255.0);
		cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);

		formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_attenuation", entity);
		formatex(tmp_debug2,charsmax(tmp_debug2),"%f", attenuation);
		cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);

		formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_flags", entity);
		formatex(tmp_debug2,charsmax(tmp_debug2),"%u", fFlags);
		cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);

		formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_pitch", entity);
		formatex(tmp_debug2,charsmax(tmp_debug2),"%i", pitch);
		cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);

		formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_name", entity);
		get_entvar(entity,var_classname,tmp_debug2,charsmax(tmp_debug2));
		cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);

		
		if (entity > MAX_PLAYERS || entity < 1)
		{
			formatex(tmp_debug,charsmax(tmp_debug),"entity_%i_info", entity);
			formatex(tmp_debug2,charsmax(tmp_debug2),"replace_sound_for_all_ents option is required!", entity);
			cfg_write_str(tmp_section_name,tmp_debug,tmp_debug2);
		}
	}

	if (entity > MAX_PLAYERS || entity < 1)
	{
		if (g_bReplaceSoundForAll)
		{
			new snd = ArrayFindString(g_aOriginalSounds, sample);
			if (snd >= 0)
			{
				ArrayGetString(g_aReplacedSounds, snd, tmp_sample, charsmax(tmp_sample));
				if (strlen(tmp_sample) > 0)
				{
					SetHookChainArg(4,ATYPE_STRING,tmp_sample)
				}
			}
		}
		return HC_CONTINUE;
	}
	else if (g_bPlayerBot[entity] && !g_bAntiespForBots)
	{
		return HC_CONTINUE;
	}
	
	static Float:vOrigin[3];
	get_entvar(entity,var_origin, vOrigin);
	
	new pack_ent_chan = fill_entity_and_channel(entity, channel);
	if (pack_ent_chan == 0)
	{
		return HC_CONTINUE;
	}
	
	static Float:vOrigin_fake[3];
	if (g_iFakeSoundMode == 1)
	{
		if (get_gametime() - g_fFakeTime > 0.1)
		{
			g_fFakeTime = get_gametime();

			vOrigin_fake[0] = floatclamp(vOrigin[0] + random_float(200.0,700.0),-8190.0,8190.0);
			vOrigin_fake[1] = floatclamp(vOrigin[1] - random_float(200.0,700.0),-8190.0,8190.0);
			vOrigin_fake[2] = floatclamp(vOrigin[2] + random_float(0.0,15.0),-8190.0,8190.0);
			emit_fake_sound(vOrigin_fake,float(volume) / 255.0, attenuation,fFlags, pitch,channel);
		}
	}
	else if (g_iFakeSoundMode > 1)
	{
		static Float:vDir[3];
		if (get_gametime() - g_fFakeTime > 0.1)
		{
			g_fFakeTime = get_gametime();
				
			for(new i = 1; i < MAX_PLAYERS + 1; i++)
			{
				if (g_bPlayerConnected[i])
				{
					get_user_aim_origin_and_dir(i, vOrigin_fake, vDir);
					
					xs_vec_mul_scalar(vDir, random_float(50.0,400.0), vDir);
					xs_vec_add(vOrigin_fake, vDir, vOrigin_fake);

					vOrigin_fake[1] = floatclamp(vOrigin_fake[1] - random_float(-150.0,150.0),-8190.0,8190.0);
					vOrigin_fake[2] = floatclamp(vOrigin_fake[2] + random_float(-50.0,50.0),-8190.0,8190.0);

					emit_fake_sound(vOrigin_fake, float(volume) / 255.0, attenuation, fFlags, pitch, channel, i);
				}
			}
		}
	}

	new snd = ArrayFindString(g_aOriginalSounds, sample);
	if (snd >= 0)
	{
		ArrayGetString(g_aReplacedSounds, snd, tmp_sample, charsmax(tmp_sample));
	}

	new new_chan = UnpackChannel(pack_ent_chan);
	new new_ent = ArrayGetCell(g_aSoundEnts,UnpackEntId(pack_ent_chan));

	if (new_ent <= MAX_PLAYERS)
	{
		set_fail_state("Failed to unpack entity or channel from packed value!");
		return HC_CONTINUE;
	}
	
	new Float:vol_mult = 255.0;

	if (g_bGiveSomeRandom)
	{
		vol_mult = 255.0 + random_float(0.0,2.0);
		attenuation = attenuation + random_float(0.0,0.01);
	}

	new Float:new_vol = float(volume) / vol_mult;

	if (new_vol < g_fMinSoundVolume)
	{
		return HC_BREAK;
	}

	if (g_iProtectStatus == 1)
		g_iProtectStatus = 2;

	rg_emit_sound_custom(new_ent, entity, new_chan, tmp_sample[0] == EOS ? sample : tmp_sample, new_vol, attenuation, fFlags, pitch, 0, vOrigin, recipients == 0, recipients > 100 ? recipients - 100 : 0);
	return HC_BREAK;
}

public send_bad_sound(id)
{
	if(!is_user_alive(id))
		return;

	static Float:vOrigin[3];

	get_entvar(id, var_origin, vOrigin);

	static Float:vOrigin_fake[3];
	vOrigin_fake[0] = floatclamp(vOrigin[0] + random_float(100.0,300.0),-8190.0,8190.0);
	vOrigin_fake[1] = floatclamp(vOrigin[1] - random_float(100.0,300.0),-8190.0,8190.0);
	vOrigin_fake[2] = floatclamp(vOrigin[2] + random_float(0.0,2.0),-8190.0,8190.0);

	set_entvar(id, var_origin, vOrigin_fake);

	for(new i = 1; i < MAX_PLAYERS + 1; i++)
	{
		if (g_bPlayerConnected[i])
		{
			// make bad for very old esp boxes
			rh_emit_sound2(id, i, CHAN_VOICE, "player/die3.wav", VOL_NORM, ATTN_NORM);
			// make bad for something new esp box
			rh_emit_sound2(id, i, CHAN_VOICE, "player/headshot1.wav", VOL_NORM, ATTN_NORM);
			rh_emit_sound2(id, i, CHAN_VOICE, "player/headshot2.wav", VOL_NORM, ATTN_NORM);
			// hide previous sounds
			rh_emit_sound2(id, i, CHAN_VOICE, "common/null.wav", VOL_NORM, ATTN_NORM);
		}
	}
	
	set_entvar(id, var_origin, vOrigin);
}

public RG_CBasePlayer_Spawn_post(const id)
{
	if(!is_user_alive(id))
		return HC_CONTINUE;
	
	g_iProtectStatus = 1;

	if (g_bCrackOldEspBox)
	{
		new Float:delay = random_float(0.5,3.0);
		set_task(delay, "send_bad_sound", id);
	}
	return HC_CONTINUE;
}

public FM_PlaybackEvent_pre(flags, invoker, eventid, Float:delay, Float:origin[3], Float:angles[3], Float:fparam1, Float:fparam2, iParam1, iParam2, bParam1, bParam2)
{
	if (invoker < 1 || invoker > MAX_PLAYERS || flags & FEV_HOSTONLY)
		return FMRES_IGNORED;

	if (!g_bAntiespForBots && g_bPlayerBot[invoker])
		return FMRES_IGNORED;

	for(new i = 0; i < sizeof(g_iEventIdx); i++)
	{
		if (g_iEventIdx[i] == eventid)
		{
			static Float:vOrigin[3];
			static Float:vEndAim[3];

			get_entvar(invoker,var_origin,vOrigin);
			get_user_aim_end(invoker,vEndAim);

			engfunc(EngFunc_SetGroupMask, 0, GROUP_OP_IGNORE);
			set_entvar(invoker,var_groupinfo, 1);

			for(new p = 1; p < MAX_PLAYERS + 1; p++)
			{
				if (g_bPlayerConnected[p])
				{
					if (p != invoker)
					{
						set_entvar(p,var_groupinfo, 0);
						if (!g_bPlayerBot[p])
						{
#if REAPI_VERSION > 524300
							if (!CheckVisibilityInOrigin(p, vOrigin) && !fm_is_visible_re(p, vEndAim))
#else 
							if (!fm_is_visible_re(p, vOrigin) && !fm_is_visible_re(p, vEndAim))
#endif
							{
								set_entvar(p,var_groupinfo, 1);
								if (g_iHideEventsMode == 1)
								{
									// >100 = player offset
									RH_SV_StartSound_pre(100 + p, invoker, CHAN_WEAPON, bParam1 ? g_sGunsSounds[i][1] : g_sGunsSounds[i][0], 255, ATTN_NORM, 0, PITCH_NORM);
								}
							}
						}
					}
					else 
					{
						set_entvar(p,var_groupinfo, 1);
					}
				}
			}

			engfunc(EngFunc_SetGroupMask, 0, GROUP_OP_NAND);
			engfunc(EngFunc_PlaybackEvent, flags, invoker, eventid, delay, origin, angles, fparam1, fparam2, iParam1, iParam2, bParam1, bParam2);
			engfunc(EngFunc_SetGroupMask, 0, GROUP_OP_AND);

			for(new p = 1; p < MAX_PLAYERS + 1; p++)
			{
				if (g_bPlayerConnected[p] || g_bPlayerBot[p])
				{
					set_entvar(invoker,var_groupinfo, 0);
				}
			}

			return FMRES_SUPERCEDE;
		}
	}
	
	return FMRES_IGNORED;
}


#define WAVE_FORMAT_PCM 1
#define BITS_PER_SAMPLE 8
#define NUM_CHANNELS 1
#define SAMPLE_RATE 22050

stock MoveSoundWithRandomTail(const path[], const dest[])
{
	new file = fopen(path, "rb", true, "GAMECONFIG");
	if (!file)
	{
		set_fail_state("Failed to open WAV source %s file.", path);
		return;
	}
	
	new file_dest = fopen(dest, "wb", true, "GAMECONFIG");
	if (!file_dest)
	{
		set_fail_state("Failed to open WAV dest %s file.", dest);
		return;
	}

	static buffer_blocks[512];
	static buffer_byte;

	fseek(file, 0, SEEK_SET);
	fseek(file_dest, 0, SEEK_SET);

	// header
	fread(file, buffer_byte, BLOCK_INT);
	fwrite(file_dest, buffer_byte, BLOCK_INT);

	// size
	new rnd_tail = random(50);
	new fileSize;
	fread(file, fileSize, BLOCK_INT);
	fwrite(file_dest, fileSize + rnd_tail, BLOCK_INT);

	// other data
	new read_bytes = 0;
	while((read_bytes = fread_blocks(file, buffer_blocks, sizeof(buffer_blocks), BLOCK_BYTE)))
	{
		fwrite_blocks(file_dest, buffer_blocks, read_bytes, BLOCK_BYTE );
	}

	fclose(file);
	// tail (unsafe but it works!)
	for(new i = 0; i < rnd_tail; i++)
	{
		fwrite(file_dest, 0, BLOCK_BYTE);
	}
	fclose(file_dest);
}

stock CreateSilentWav(const path[],Float:duration = 1.0)
{
    new dataSize = floatround(duration * SAMPLE_RATE); // Total samples
    new fileSize = 44 + dataSize - 8; 

    new file = fopen(path, "wb", true, "GAMECONFIG");
    if (file)
    {
        // Writing the WAV header
		// 1179011410 = "RIFF"
        fwrite(file, 1179011410, BLOCK_INT);
        fwrite(file, fileSize, BLOCK_INT); // File size - 8
		// 1163280727 = "WAVE"
        fwrite(file, 1163280727, BLOCK_INT);
		// 544501094 == "fmt "
        fwrite(file, 544501094, BLOCK_INT);
        fwrite(file, 16, BLOCK_INT); // Subchunk1Size (16 for PCM)
        fwrite(file, WAVE_FORMAT_PCM, BLOCK_SHORT); // Audio format (1 for PCM)
        fwrite(file, NUM_CHANNELS, BLOCK_SHORT); // NumChannels
        fwrite(file, SAMPLE_RATE, BLOCK_INT); // SampleRate
        fwrite(file, SAMPLE_RATE * NUM_CHANNELS * BITS_PER_SAMPLE / 8, BLOCK_INT); // ByteRate
        fwrite(file, NUM_CHANNELS * BITS_PER_SAMPLE / 8, BLOCK_SHORT); // BlockAlign
        fwrite(file, BITS_PER_SAMPLE, BLOCK_SHORT); // BitsPerSample
		// 1635017060 = "data"
        fwrite(file, 1635017060, BLOCK_INT);
        fwrite(file, dataSize, BLOCK_INT); // Subchunk2Size

        // Writing the silent audio data
        for (new i = 0; i < dataSize; i++)
        {
            fwrite(file, 128, BLOCK_BYTE); // Middle value for 8-bit PCM to represent silence
        }

        fclose(file);
    }
    else
    {
        set_fail_state("Failed to create WAV file.");
    }
}

new const g_CharSet[] = "abcdefghijklmnopqrstuvwxyz";

stock RandomString(dest[], length)
{
    new i, randIndex;
    new charsetLength = strlen(g_CharSet);

    for (i = 0; i < length; i++)
    {
        randIndex = random(charsetLength);
        dest[i] = g_CharSet[randIndex];
    }

    dest[length - 1] = EOS;  // Null-terminate the string
}

RandomSoundPostfix(const prefix[], dest[], length)
{
	static rnd_postfix = 0;
	if (rnd_postfix == 0)
		rnd_postfix = random_num(30100000, 99999999);

	
	formatex(dest,length,"%s%i.wav",prefix,rnd_postfix);

	new hash[64];
	hash_string(dest, Hash_Md5, hash, charsmax(hash));

	formatex(dest,length,"%s%s.wav",prefix,hash);


	rnd_postfix-=random_num(1,10000);
	if (rnd_postfix < 10010000) 
		rnd_postfix = 99999999;
}

StandSoundPostfix(const prefix[], dest[], length)
{
	static stnd_postfix = 59999999;
	formatex(dest,length,"%s%i.wav",prefix,stnd_postfix);

	new hash[64];
	hash_string(dest, Hash_Md5, hash, charsmax(hash));

	formatex(dest,length,"%s%s.wav",prefix,hash);

	stnd_postfix-= 599;
	if (stnd_postfix < 10000599) 
		stnd_postfix = 99999999;
}

stock PackChannelEnt(num1, num2)
{
    return (num1 & 0xFF) | ((num2 & 0xFFFFFF) << 8);
}

stock UnpackChannel(packedNum)
{
    return packedNum & 0xFF;
}

stock UnpackEntId(packedNum)
{
    return (packedNum >> 8) & 0xFFFFFF;
}

stock bool:sound_exists(path[])
{
	new fullpath[256];
	formatex(fullpath,charsmax(fullpath),"sound/%s",path)
	return file_exists(fullpath,true) > 0;
}

stock trim_to_dir(path[])
{
    new len = strlen(path);
    len--;
    for(new i = len; i >= 0; i--)
    {
        if(path[i] == '/' || path[i] == '\\')
        {
            path[i] = EOS;
            break;
        }
    }
}

stock bool:fm_is_visible_re(index, const Float:point[3], ignoremonsters = 0) {
	static Float:start[3], Float:view_ofs[3];
	get_entvar(index, var_origin, start);
	get_entvar(index, var_view_ofs, view_ofs);
	xs_vec_add(start, view_ofs, start);

	engfunc(EngFunc_TraceLine, start, point, ignoremonsters, index, 0);

	static Float:fraction;
	get_tr2(0, TR_flFraction, fraction);
	if (fraction == 1.0)
		return true

	return false
}

stock get_user_aim_end(index, Float:vEnd[3])
{
	static Float:vOrigin[3];
	static Float:vTarget[3];
	get_user_aim_origin_and_dir(index, vOrigin, vTarget);

	xs_vec_mul_scalar(vTarget, 4096.0, vTarget);
	xs_vec_add(vOrigin, vTarget, vTarget);

	trace_line(index, vOrigin, vTarget, vEnd);
}

stock get_user_aim_origin_and_dir(index, Float:vOrigin[3], Float:vDir[3])
{
	static Float:vOffset[3];
	get_entvar(index, var_origin, vOrigin);
	get_entvar(index, var_view_ofs, vOffset);
	xs_vec_add(vOrigin, vOffset, vOrigin );
	get_entvar(index, var_v_angle, vDir);
	angle_vector(vDir, ANGLEVECTOR_FORWARD, vDir);
}
