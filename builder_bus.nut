
class BuildBusRoute extends Task {

	towns = [];
	cargo = null;
	vgroup = null;

	// towns is an array of town IDs
	constructor(parentTask, towns, cargoID) {
		Task.constructor(parentTask, null);
		this.towns = towns;
		cargo = cargoID;
		vgroup = AIGroup.CreateGroup(AIVehicle.VT_ROAD);
		subtasks = [];
	}
	
	function _tostring() {
		return "BuildBusRoute";
	}
	
	function Run() {

		local stations = {};
		local town;
		foreach (town in this.towns) {

			local location = AITown.GetLocation(town);
			
			local depot = FindClosestDepot(location, AITile.TRANSPORT_ROAD);
			if (depot == null) {
				local d = BuildTruckDepot(this, location);
				d.Run();
				depot = d.depot;
				if (depot == null) {
					throw TaskFailedException("unable to build depot");
				}
			}

			local bobj = BuildBusStationInTown(this, town);
			subtasks = [ bobj ];
			RunSubtasks();
			stations[town] <- bobj.station;
		}

		// TODO: need to sort by distance to each other
		local i, j, town1, town2, station;
		for (i=0; i < towns.len(); i++) {
			town1 = towns[i];
			station = stations[town1];
			subtasks.append(BuildRoad(this, station, town1));
			for (j=0; j < towns.len(); j++) {
				if (town1 == town2) { continue }
				subtasks.append(BuildRoad(this, station, town2));
			}
		}
	}
}

class BuildBusStation extends Task {

	// AIRoad.ROADVEHTYPE_TRUCK or AIRoad.ROADVEHTYPE_BUS
	constructor(parentTask, location, ttype = AIRoad.ROADVEHTYPE_BUS) {
		Task.constructor(parentTask, null);
		BuildTruckStation.constructor(parentTask, location, ttype);
	}
	
	function _tostring() {
		return "BuildBusStation";
	}
}

class BuildBusStationInTown extends Task {

	town = null;
	station = null;
	RADIUS = 40;

	constructor(parentTask, town) {
		Task.constructor(parentTask, null);
		this.town = town;
	}

	function _tostring() {
		return "BuildBusStationInTown";
	}

	function Run() {
		station = BuildStopInTown(town);
		if (station == null) {
			throw TaskFailedException("unable to build station in town ", AITown.GetName(town)); 
		}
	}

	function BuildStopInTown(townID) {

		local stat = AIStation.STATION_NEW;
		local stype == AIRoad.ROADVEHTYPE_BUS) {

		local tiles = AITileList();
		SafeAddRectangle(tiles, AITown.GetLocation(townID), this.RADIUS);

		local valfunc = function(tile, townID) {
			return AITown.IsWithinTownInfluence(townID, tile);
		}
		tiles.Valuate(valfunc, townID);
		tiles.KeepValue(1);

		tiles.Valuate(AIRoad.IsRoadTile);
		tiles.KeepValue(1);

		tiles.Valuate(AITile.GetCargoAcceptance, cargoID, 1, 1, 1);
		tiles.KeepAboveValue(1);

		tiles.Valuate(AITile.GetDistanceManhattanToTile, AITown.GetLocation(townID));
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		// find buildable spots along the road
		local t, sur, s, z, ret;
		foreach (t,z in tiles) {
			sur = AITileList();
			SafeAddRectangle(sur, t, 1);

			sur.Valuate(AIRoad.IsRoadTile);
			sur.KeepValue(1);
			foreach (s,z in sur) {
				if (AIRoad.BuildDriveThroughRoadStation(t,s,stype,stat)) {
					return t;
				}
			}
		}
		return null;
	}
}

