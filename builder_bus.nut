
class BuildBusRoute extends Task {

	towns = [];
	stations = {};
	depots = {};
	cargo = null;
	vgroup = null;
	vehicles = [];

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

		local town;
		foreach (town in this.towns) {

			local location = AITown.GetLocation(town);
			local name = AITown.GetName(town);
			
			local depot = FindClosestDepot(location, AITile.TRANSPORT_ROAD);
			if (depot == null) {
				local d = BuildTruckDepot(this, location);
				d.Run();
				depot = d.depot;
				if (depot == null) {
					throw TaskFailedException("unable to build depot");
				}
				depots[town] <- depot;
			}

			Debug("build station in town ", name);
			local bobj = BuildBusStationInTown(this, town, cargo);
			subtasks = [ bobj ];
			RunSubtasks();
			stations[town] <- bobj.station;
			Debug("station built is at ", stations[town]);
		}

		// TODO: need to sort by distance to each other
		local i, j, town1, town2, station1, station2;
		foreach (town1 in this.towns) {
			for (j=0; j < towns.len(); j++) {
				town2 = towns[j];
				if (town1 != town2) {
					subtasks.append(BuildTruckRoad(this, stations[town1], stations[town2]));
				}
			}
		}
		RunSubtasks();

		local eID = AllocateTruck(this.cargo);
		town = towns[0];
		local depot = this.depots[town];
		for (i=0; i < towns.len(); i++) {
		foreach (town in towns) {
			local depot = this.depots[town];
			local veh = AIVehicle.BuildVehicle(depot, eID);
		}

		// 1 -> 2 -> 3 -> 4 -> 5 -> 4 -> 3 -> 2
	}
}

class BuildBus extends Task {

	depot = null;
	cargo = null;

	constructor(parentTask, depot, cargo) {
		Task.constructor(parentTask, null);
		this.depot = depot;
		this.cargo = cargo;
	}
	
	function _tostring() {
		return "BuildBusStation";
	}

	function Run() {
		local eID = AllocateTruck(this.cargo);
		veh = AIVehicle.BuildVehicle(this.depot, eID);
		return
	}

	function AllocateTruck(cargo) {
		local z = 0;
		local ctl = AICargo.GetCargoLabel(cargo);
		AILog.Info("Pick truck for " + ctl);

		local printvals = function(msg, alist) {
			return;
			local item;
			local z;
			local i = 0;
			AILog.Info(msg);
			AILog.Info("-----");
			foreach (item,z in alist) {
				local ct = AIEngine.GetCargoType(item);
				local ctn = AICargo.GetCargoLabel(ct);
				local n = AIEngine.GetName(item);
				AILog.Info(i + " " + n + " " + ct + " " + ctn);
				i++;
			}
			AILog.Info("-----");
		}

		local vlist = AIEngineList(AIVehicle.VT_ROAD);
		printvals("available trucks:", vlist);

		vlist.Valuate(AIEngine.GetCargoType);
		vlist.KeepValue(cargo);
		printvals("just cargo type" + cargo, vlist);

		vlist.Valuate(AIEngine.IsBuildable);
		vlist.KeepValue(1);
		printvals("only buildable", vlist);

		vlist.Valuate(AIEngine.GetRoadType);
		vlist.KeepValue(AIRoad.ROADTYPE_ROAD);
		printvals("just vehicles of our road type", vlist);

		vlist.Valuate(AIEngine.GetCapacity);
		vlist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		printvals("sorted by capacity", vlist);

		local eID = vlist.Begin();
		AILog.Info("Chose " + AIEngine.GetName(eID));
		return eID;
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
	cargo = null;
	station = null;
	RADIUS = 40;

	constructor(parentTask, town, cargo) {
		Task.constructor(parentTask, null);
		this.town = town;
		this.cargo = cargo;
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
		local stype = AIRoad.ROADVEHTYPE_BUS;

		local tiles = AITileList();
		SafeAddRectangle(tiles, AITown.GetLocation(townID), this.RADIUS);

		local valfunc = function(tile, townID) {
			return AITown.IsWithinTownInfluence(townID, tile);
		}
		tiles.Valuate(valfunc, townID);
		tiles.KeepValue(1);

		tiles.Valuate(AIRoad.IsRoadTile);
		tiles.KeepValue(1);

		tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, 1);
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

