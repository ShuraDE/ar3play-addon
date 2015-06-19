#include "init.hpp"

private "_getUnitData";
private "_arePlayersConnected";
private "_sendDataLoop";
private "_echoLoop";

_logscript = compile preprocessFileLineNumbers "\ar3play\vendor\sock-rpc\log.sqf";
call _logscript;

_sockscript = compile preprocessFileLineNumbers "\ar3play\vendor\sock-rpc\sock.sqf";
call _sockscript;

_getUnitData = compile preprocessFileLineNumbers "\ar3play\getUnitData.sqf";

_arePlayersConnected = {
	private ["_result", "_now"];
	_result = ({isPlayer _x} count playableUnits) > 0;
	if (_result) then {
		AR3PLAY_MOST_RECENT_PLAYER_DETECTED = time;
	} else {
		_result = AR3PLAY_MOST_RECENT_PLAYER_DETECTED > (time - AR3PLAY_TIMEOUT_PLAYERS);
	};
	 _result
};

_missionStarted = {

	_result = false;
	{
	 	if (isPlayer _x && alive _x) then {
	 		_newDir = floor getDir _x; // DO AVOID FLOATS if we want to compare numbers afterwards
	 		_oldDir = _x getVariable ['ar3play_direction', -1];

	 		if (_oldDir == -1) then {
	 			_x setVariable ['ar3play_direction', _newDir];
	 		} else {
	 			if (_newDir != _oldDir) then {
	 				TRACE_3("player-controlled unit turned (name, olddir, newdir)", name _x, _oldDir, _newDir);
					_result = true;
	 			};
	 		};
	 	};
	} forEach playableUnits;

	_result
};

_sendDataLoop = {
	private "_getUnitData";
	private "_arePlayersConnected";
	
	private "_lastUnitCount";
	private "_lastUnitIDS";
	private "_lastUnitsIdentification";

	_getUnitData = _this select 0;
	_arePlayersConnected = _this select 1;

	while {(call _arePlayersConnected) && (AR3PLAY_ENABLE_REPLAY)} do {
		_unitsDataArray = [];

		{
			if ((side _x != sideLogic) && (_x isKindOf "AllVehicles")) then {
				_unitData = [_x] call _getUnitData;
				if ((_unitData select 7) != "iconObject_1x1") then {
					_unitsDataArray pushBack _unitData;
					_unitsIDs pushBack (_unitData select 0);
				};
			};
		} forEach allUnits + allDead + vehicles;
		
		//prüfen ob die sich die anzahl der einheiten reduziert hat um sie ggf. zu entfernen
		//damit die einheit entfernt wird, muss sie noch einmalig gesendet werden
		//setzen des health status auf dead
		if ((_lastUnitCount > 0) && (_lastUnitCount > count _unitsDataArray) && (count _lastUnitsIdentification > 0)) then {
			_unitDiff = _unitsIDs - _lastUnitIDS;
			{
				_searchID = _x;
				{
					if ((_x select 0) = _searchID) then {
						_x set [6, 'dead'];
						_unitsDataArray pushBack _x;
					}
				} forEach _lastUnitsIdentification;
				
			} forEach _unitDiff;
		};
		_lastUnitIDS = + _unitsIDs;
		_lastUnitCount = count _unitsDataArray;
		_lastUnitsIdentification = + _unitsDataArray;
		
		['setAllUnitData', [_unitsDataArray]] call sock_rpc;
		sleep 1;
	};
	['missionEnd', ['replay disabled or players left']] call sock_rpc;
};

//--------------------------------------------------------------

LOG("ar3play: loaded. waiting for mission start...");

if (isDedicated) then {

	addMissionEventHandler ["Ended", {
		LOG("ar3play: mission ended. stopping updates, sending endMission.");
		AR3PLAY_ENABLE_REPLAY = false;
		sleep 2;
		['missionEnd', ['mission ended event']] call sock_rpc;
	}];

	waitUntil _missionStarted;

	LOG("ar3play: first player connected and alive. starting to send updates...");

	['missionStart', [missionName, worldName]] call sock_rpc;
	['setIsStreamable', [AR3PLAY_IS_STREAMABLE]] call sock_rpc;
	[_getUnitData, _arePlayersConnected] spawn _sendDataLoop;
};
