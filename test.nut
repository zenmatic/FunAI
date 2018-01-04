class TestBusRoute extends Strategy {
	desc = "test a bus route";

	function Start() {
		local towns = AITownList();
		towns.Valuate(AITown.GetPopulation);
		towns.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		local town1 = towns.Begin();
		local town2 = towns.Next();
		local town3 = towns.Next();
		local cargoIDs = GenCargos();
		local cargo = cargoIDs.PASS;

		tasks.append(BuildBusRoute(null, [town1, town2, town3], cargo));
	}
}

class TestTruckRoute extends SimpleSuppliesStrategy {
	desc = "test a truck route";

	function Start() {
		Wake();
	}

	function Wake() {
		local routelist = FindSupplyRoutes();
		if (routelist.len() > 0) {
			local r = routelist.pop();
			routes.append(r);
			local cargo = r[0];
			local producer = AIIndustry.GetLocation(r[1]);
			local consumer = AIIndustry.GetLocation(r[2]);
			Debug("prod=", AIIndustry.GetName(r[1]), " cons=", AIIndustry.GetName(r[2]));
			tasks.append(BuildTruckRoute(null, producer, consumer, cargo));
		}
	}
}

class BuildCoalLine extends BuildNamedCargoLine {

	cargo = null;

	constructor(parentTask=null, cargo=null) {
		Task.constructor(parentTask, null);
		this.cargo = cargo;
		Debug("cargo is ", cargo);
	}

	function _tostring() {
		return "BuildCoalLine";
	}
	
	function Run() {
		local prodlist = AIIndustryList_CargoProducing(this.cargo);
		local acclist = AIIndustryList_CargoAccepting(this.cargo);
		Debug("prodlist count=" + prodlist.Count());
		local producer = prodlist.Begin();
		Debug("acclist count=" + acclist.Count());
		local consumer = acclist.Begin();
		local r = CargoRoute(producer, consumer, this.cargo);
		subtasks = [
			BuildNamedCargoLine(this, producer, consumer, this.cargo),
		];

		RunSubtasks();
	}
}

class TestOilToTown extends Strategy {
	desc = "make oil route to nearest town";

	function Start() {
		local cargoIDs = GenCargos();
		local cargo = cargoIDs.OIL_;
		local producing = AIIndustryList_CargoProducing(cargo);
		producing.Valuate(AIIndustry.IsBuiltOnWater);
		producing.KeepValue(1);
		Debug("len is ", producing.Count());
		local oilrig = producing.Begin();
		Debug("name is ", AIIndustry.GetName(oilrig));
		local oilrig_loc = AIIndustry.GetLocation(oilrig);

		local towns = AITownList();
		towns.Valuate(AITown.GetDistanceManhattanToTile, oilrig_loc);
		towns.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		local town = towns.Begin();
		Debug("nearest town is ", AITown.GetName(town));
		local town_loc = AITown.GetLocation(town);

		local obj_depot = BuildWaterDepotBetween(null, town_loc, oilrig_loc);
		local obj_dock = BuildDock(null, town_loc);
		tasks = [
			obj_depot,
			obj_dock,
		];
		RunTasks();
		tasks = [
			BuildShipRoute(null, obj_depot.depot, oilrig_loc, obj_dock.dock, cargo),
		];

	}
}

class TestIndustryInTown extends Strategy {
	function Start() {
		local industries = AIIndustryList();
		local i;
		foreach (industry,_ in industries) {
			local ret = IsIndustryInTown(industry);
			Debug("ret is ", ret);
		}
	}
}

class TestExpandingStations extends Strategy {
	desc = "test expanding stations per Wake call";
	infos = [];

	function Start() {
		//TestRectangles();
		BuildFirstStation();
	}

	function Wake() {
		Debug("Wake() called");
		ExpandStation();
	}

	function BuildFirstStation() {
		local tilecount = AIMap.GetMapSize();
		local xtiles = AIMap.GetMapSizeX();
		local ytiles = AIMap.GetMapSizeY();
		local xcenter = xtiles / 2;
		local ycenter = ytiles / 2;
		local center = AIMap.GetTileIndex(xcenter, ycenter);
		local front =  AIMap.GetTileIndex(xcenter + 1, ycenter);
		local roadtype = AIRoad.ROADVEHTYPE_TRUCK;
		local opt =  AIStation.STATION_NEW;
		Debug("xcenter=", xcenter, " ycenter=", ycenter);
		Debug("center=", center, " front=", front);
		Debug("opt=", opt);

		AIRoad.BuildRoadStation(center, front, roadtype, opt);
		this.infos = [
			{ stationloc = center, }
		];
	}

	function ExpandStation() {
		local ret = false;

		local stationloc = this.infos[0].stationloc;
		local stationfront = AIRoad.GetRoadStationFrontTile(stationloc);
		local stationID = AIStation.GetStationID(stationloc);
		local roadtype = AIRoad.ROADVEHTYPE_TRUCK;
		local opt =  AIStation.STATION_JOIN_ADJACENT;

		local tiles = AITileList();
		SafeAddRectangle(tiles, stationloc, 0, 2);
		tiles.RemoveValue(stationloc);
		tiles.Valuate(AITile.IsBuildable);
		tiles.KeepValue(1);
		tiles.Valuate(AITile.GetSlope);
		tiles.KeepValue(AITile.SLOPE_FLAT);
		tiles.Valuate(AITile.GetDistanceManhattanToTile, stationloc);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		Debug("tile count=", tiles.Count());
		if (tiles.IsEmpty()) {
			Debug("no available tiles found");
			return false;
		}

		local t;
		local i = 1;
		for (t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
			local x = AIMap.GetTileX(t) + 1;
			local y = AIMap.GetTileY(t);
			local front =  AIMap.GetTileIndex(x, y);
			ret = AIRoad.BuildRoadStation(t, front, roadtype, opt);
			Debug("t=", t, " front=", front, " roadtype=", roadtype, " opt=", opt);	
			PrintError(ret);
			if (ret) { break }
			//AISign.BuildSign(t, ""+i);
			i++;
		}
		return ret;

		local maketile = function (x,y) {
			return AIMap.GetTileIndex(x, y);
		}

		local stype = AIRoad.GetRoadVehicleTypeForCargo(this.cargo);
		local x = AIMap.GetTileX(loc);
		local y = AIMap.GetTileY(loc);
		local arr = [maketile(x+1,y), maketile(x-1,y), maketile(x,y+1), maketile(x,y-1)];
		local t;
		local stationface;
		foreach (t in arr) {
			ret = AIRoad.BuildRoadStation(loc, t, stype, stationID); 
			Debug("t=" + t + " loc=" + loc + " ret=" + ret);
			if (ret == true) {
				stationface = t;
				Debug("built stop at " + loc + " facing " + t);
				break;
			}
		}
		if (ret == false) {
			PrintError();
			return false;
		}
		Debug("t=" + t);
		ret = BuildRoad(stationface, stationloc);
		ret = BuildRoad(loc, stationface);
		return ret;
	}
}

class TestStuff extends Strategy {
	desc = "test stuff";

	function Start() {
		//TestRectangles();
		//LinedStations();
		//Directions();
		DirectionFromCenter();
		//MapEveryOther();
		//StationFacingIndustry();
	}

	function StationFacingIndustry() {
		local cargoIDs = GenCargos();
		local cargoID = cargoIDs.COAL;
		local prodlist = AIIndustryList_CargoProducing(cargoID);
		local acclist = AIIndustryList_CargoAccepting(cargoID);
		AILog.Info("prodlist count=" + prodlist.Count());
		local pID = prodlist.Begin();
		AILog.Info("acclist count=" + acclist.Count());
		local aID = acclist.Begin();

		local stype = "industry";
		local r = Route(routename, cargoID, true);
		local prod_t = r.GetResInfo(stype, pID);
		local acc_t = r.GetResInfo(stype, aID);
		local ploc = prod_t.stationloc;
		local aloc = acc_t.stationloc;
		local dir = FindDirection(ploc, aloc);
	}

	function MapEveryOther() {
		local xtiles = AIMap.GetMapSizeX();
		local ytiles = AIMap.GetMapSizeY();
		local tiles = AITileList();

		for (local x=1; x < xtiles; x += 2) {
			for (local y=1; y < ytiles; y += 2) {
				local tile = AIMap.GetTileIndex(x, y);
				local coords = " (" + x + "," + y + ")";
				AISign.BuildSign(tile, coords);
			}
		}
	}

	function GetCenter() {
		local tilecount = AIMap.GetMapSize();
		local xtiles = AIMap.GetMapSizeX();
		local ytiles = AIMap.GetMapSizeY();
		local xcenter = xtiles / 2;
		local ycenter = ytiles / 2;
		return [xcenter, ycenter];
	}

	function GetCenterTile() {
		local arr = GetCenter();
		return AIMap.GetTileIndex(arr[0], arr[1]);
	}

	function Directions() {
		local arr = GetCenter();
		local xcenter = arr[0];
		local ycenter = arr[1];

		local makestation = function (name, x1,y1,x2,y2) {
			local roadtype = AIRoad.ROADVEHTYPE_TRUCK;
			local opt =  AIStation.STATION_NEW;

			local sloc = AIMap.GetTileIndex(x1, y1);
			local front =  AIMap.GetTileIndex(x2, y2);
			Debug(name, " sloc=", sloc, " front=", front);
			local coords = " (" + x1 + "," + y1 + ")";

			AISign.BuildSign(sloc, name + coords)
			AISign.BuildSign(front, "front")
			//AIRoad.BuildRoadStation(sloc, front, roadtype, opt);
		};

		local x = xcenter;
		local y = ycenter;
		makestation("SW", x,y, x+1,y);
		x = xcenter + 5;
		makestation("NE", x,y, x-1,y);
		x = xcenter + 10;
		makestation("SE", x,y, x,y+1);
		x = xcenter + 15;
		makestation("NW", x,y, x,y-1);
	}

	function DirectionFromCenter() {
		local center = GetCenterTile();

		AISign.BuildSign(center, "center tile");

		local industries = AIIndustryList();
		local iID, loc;
		foreach (iID, _ in industries) {
			loc = AIIndustry.GetLocation(iID);
			local name = AIIndustry.GetName(iID);
			local dir = FindDirection(center, loc);
			local cx = AIMap.GetTileX(center);
			local cy = AIMap.GetTileY(center);
			local lx = AIMap.GetTileX(loc);
			local ly = AIMap.GetTileY(loc);
			Debug(center, "(", cx, ",", cy, ") to ", loc, " (", lx, ",", ly, ") (", name, ") is ", dir);
		}
	}

	function FindDirection(fromtile, totile) {
		local dir = StationDirection(fromtile, totile);
		return DirectionName(dir);

		/*
		local fromx = AIMap.GetTileX(fromtile);
		local fromy = AIMap.GetTileY(fromtile);
		local tox = AIMap.GetTileX(totile);
		local toy = AIMap.GetTileY(totile);

		if (fromtile == totile) {
			return null;
		}

		local ns = null;
		local ew = null;
		if (fromx > tox) {
			ns = "N";
		} else {
			ns = "S";
		}

		if (fromy > toy) {
			ew = "W";
		} else {
			ew = "E";
		}
		return ns + ew;
		*/
	}

	function LinedStations() {
		local tilecount = AIMap.GetMapSize();
		local xtiles = AIMap.GetMapSizeX();
		local ytiles = AIMap.GetMapSizeY();
		local xcenter = xtiles / 2;
		local ycenter = ytiles / 2;
		local center = AIMap.GetTileIndex(xcenter, ycenter);
		local front =  AIMap.GetTileIndex(xcenter + 1, ycenter);
		local roadtype = AIRoad.ROADVEHTYPE_TRUCK;
		local opt =  AIStation.STATION_JOIN_ADJACENT;
		Debug("xcenter=", xcenter, " ycenter=", ycenter);
		Debug("center=", center, " front=", front);
		Debug("opt=", opt);

		AIRoad.BuildRoadStation(center, front, roadtype, opt);

		local tiles = AITileList();
		SafeAddRectangle(tiles, center, 0, 1);
		tiles.RemoveValue(center);
		tiles.Valuate(AITile.IsBuildable);
		tiles.KeepValue(1);
		tiles.Valuate(AITile.GetSlope);
		tiles.KeepValue(AITile.SLOPE_FLAT);
		tiles.Valuate(AITile.GetDistanceManhattanToTile, center);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		Debug("tile count=", tiles.Count());
		local t;
		local i = 1;
		for (t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
			local x = AIMap.GetTileX(t) + 1;
			local y = AIMap.GetTileY(t);
			local front =  AIMap.GetTileIndex(x, y);
			local ret = AIRoad.BuildRoadStation(t, front, roadtype, opt);
			Debug("t=", t, " front=", front, " roadtype=", roadtype, " opt=", opt);	
			PrintError(ret);
			//AISign.BuildSign(t, ""+i);
			i++;
		}
	}

	function TestRectangles() {
		local tilecount = AIMap.GetMapSize();
		local xtiles = AIMap.GetMapSizeX();
		local ytiles = AIMap.GetMapSizeY();
		local xcenter = xtiles / 2;
		local ycenter = ytiles / 2;
		local center = AIMap.GetTileIndex(xcenter, ycenter);
		Debug("xcenter=", xcenter, " ycenter=", ycenter);

		local tiles = AITileList();
		SafeAddRectangle(tiles, center, 0, 4);
		//Debug("tile count=", tiles.Count());
		tiles.Valuate(AITile.GetDistanceManhattanToTile, center);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		local t;
		local i = 1;
		for (t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
			AISign.BuildSign(t, ""+i);
			i++;
		}
	}

}

class TestTransferStrategy extends Strategy {
	desc = "try transferring stuff";

	function Start() {

		local cargoIDs = GenCargos();
		local cargo = cargoIDs.MAIL;
		local towns = AITownList();
		local town1 = towns.Begin();
		local town2 = towns.Next();

		local producer_info = {
			id = town1,
			type = AISubsidy.SPT_TOWN,
		}
		local consumer_info = {
			id = town2,
			type = AISubsidy.SPT_TOWN,
		}
		tasks.append(BuildTransferCargoLine(null, producer_info, consumer_info, cargo));
	}
}

class BuildRoadStopInTown extends Builder {

	location = null;
	town = null;
	town_name = null;
	cargo = null;
	cargo_label = null;
	network = null;

	constructor(parentTask, town, cargo, network) {
		Task.constructor(parentTask, null);
		this.town = town;
		this.location = AITown.GetLocation(town);
		this.town_name = AITown.GetName(town);
		this.cargo_label = AICargo.GetCargoLabel(cargo);
		this.cargo = cargo;
		this.network = network;
	}

	function _tostring() {
		return "BuildRoadStopInTown: build road stop in " + town_name +
			"for cargo " + cargo_label;
	}

	function Run() {
		local stat = AIStation.STATION_NEW;
		local stype = AIRoad.GetRoadVehicleTypeForCargo(cargo);
		local stoptype = "UNKNOWN";
		if (stype == AIRoad.ROADVEHTYPE_BUS) {
			stoptype = "bus";
		} else if (stype == AIRoad.ROADVEHTYPE_TRUCK) {
			stoptype = "truck";
		}
		Debug("build ", stoptype, " stop for ", cargo, " in ", town_name);

		local printvals = function(arr, msg) {
			Debug(msg, ":", arr.Count());
		}

		local valfunc = function(tile, town) {
			return AITown.IsWithinTownInfluence(town, tile);
		}
		local tiles = AITileList();
		SafeAddRectangle(tiles, AITown.GetLocation(town), 30);
		tiles.Valuate(valfunc, town);
		tiles.KeepValue(1);
		printvals(tiles, "valfun/AITown.IsWithinTownInfluence");

		tiles.Valuate(AIRoad.IsRoadTile);
		tiles.KeepValue(1);
		printvals(tiles, "AIRoad.IsRoadTile");

		tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, 1);
		tiles.KeepAboveValue(1);
		printvals(tiles, "AITile.GetCargoAcceptance");

		tiles.Valuate(AITile.GetDistanceManhattanToTile, AITown.GetLocation(town));
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		/* find buildable spots along the road */
		local t, sur, s, z, ret, stationID;
		foreach (t,z in tiles) {
			sur = AITileList();
			SafeAddRectangle(sur, t, 1);

			sur.Valuate(AIRoad.IsRoadTile);
			sur.KeepValue(1);
			foreach (s,z in sur) {
				ret = AIRoad.BuildDriveThroughRoadStation(t,s,stype,stat);
				if (ret) {
					network.stations.append(t);
					return;
				}
			}
		}
		Debug("Cannot build station");
		throw TaskFailedException();
	}
}

class BuildStationAtLocation extends BuildCargoStation {

	constructor(parentTask, location, direction, network, destination, cargo, platformLength) {
		BuildCargoStation.constructor(parentTask, location, direction, network, null, null, cargo, false, platformLength);
	}

	/**
	 * Build station platform. Returns stationID.
	 */
	function BuildPlatform() {
		// template is oriented NW->SE
		local direction;
		if (this.rotation == Rotation.ROT_0 || this.rotation == Rotation.ROT_180) {
			direction = AIRail.RAILTRACK_NW_SE;
		} else {
			direction = AIRail.RAILTRACK_NE_SW;
		}
		
		// on the map, location of the station is the topmost tile
		local platform;
		if (this.rotation == Rotation.ROT_0) {
			platform = GetTile([0, 0]);
		} else if (this.rotation == Rotation.ROT_90) {
			platform = GetTile([0, platformLength-1]);
		} else if (this.rotation == Rotation.ROT_180) {
			platform = GetTile([0, platformLength-1]);
		} else if (this.rotation == Rotation.ROT_270) {
			platform = GetTile([0,0]);
		} else {
			throw "invalid rotation";
		}
		
		// don't try to build twice
		local stationID = AIStation.GetStationID(platform);
		if (AIStation.IsValidStation(stationID)) return stationID;
		
		AIRail.BuildRailStation(platform, direction, 1, platformLength, AIStation.STATION_NEW);
		CheckError();
		return AIStation.GetStationID(platform);
	}

	function _tostring() {
		return "BuildStationAtLocation " + location;
	}

}

// builds transfer station just outside of town and link it
class BuildTransferNearTown extends Builder {

	location = null;
	town = null;
	town_name = null;
	cargo = null;
	cargo_label = null;
	direction = null;
	destination = null;
	network = null;

	constructor(parentTask, town, destination, cargo, network) {
		Task.constructor(parentTask, null);
		this.town = town;
		this.location = AITown.GetLocation(town);
		this.town_name = AITown.GetName(town);
		this.cargo = cargo;
		this.cargo_label = AICargo.GetCargoLabel(cargo);
		this.direction = StationDirection(location, destination);
		this.destination = destination;
		this.network = network;
	}

	function _tostring() {
		return "BuildTransferNearTown: build transfer near " + town_name +
			"for cargo " + cargo_label;
	}

	function Run() {
		local rot = BuildTerminusStation.StationRotationForDirection(direction);
		local sites = GetStationSites(location, rot, destination);
		if (sites.IsEmpty()) {
			Debug("Cannot build station");
			throw TaskFailedException("no sites found");
		}

		local site = sites.Begin();
		do {
			try {
				local platformLength = 4;
				local doubleTrack = true;
				Debug("site is ", site);
				subtasks = [ BuildTerminusStation(this, site, direction, network, town, doubleTrack, platformLength) ];
				//subtasks = [ BuildStationAtLocation(this, site, direction, network, town, cargo, platformLength) ];
				RunSubtasks();
				CheckError();
				Debug("adding site ", site, "to stations");
				network.stations.append(site);
				return;
			} catch (e) {
				if (typeof(e) == "instance" && (e instanceof TaskFailedException)) {
					Warn("failed to be build station at site ", site);
					site = sites.Next();
				} else {
					Error("Unexpected error");
				}
			}
		} while (!sites.IsEnd());
	}

	function GetStationSites(location, stationRotation, destination) {
		local CARGO_STATION_LENGTH = 3;
		local area = AITileList();
		SafeAddRectangle(area, location, 30);
		Debug("after SafeAddRectangle is ", area.Count());

		area.Valuate(AITile.GetDistanceManhattanToTile, location);
		Debug("after GetDistanceManhattanToTile is ", area.Count());
		area.KeepAboveValue(5);
		Debug("after KeepAboveValue(5) is ", area.Count());
		area.KeepBelowValue(15);
		Debug("after KeepBelowValue(10) is ", area.Count());

		area.Valuate(AITile.GetSlope);
		area.KeepValue(AITile.SLOPE_FLAT);
		Debug("after AITile.GetSlope is ", area.Count());
		
		// room for a station
		area.Valuate(IsBuildableRectangle, stationRotation, [0, -1], [1, CARGO_STATION_LENGTH + 1], true);
		area.KeepValue(1);
		Debug("after IsBuildableRectangle is ", area.Count());
		
		// pick the tile farthest from the destination for increased profit
		area.Valuate(AITile.GetDistanceManhattanToTile, destination);
		area.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		Debug("after AITile.GetDistanceManhattanToTile is ", area.Count());
		
		return area;
	}
}

class TestStationInCity extends Strategy {
	desc = "test building a station in a city";
	network = null;

	constructor() {
		local CARGO_MIN_DISTANCE = 30;
		local CARGO_MAX_DISTANCE = 75;
		local CARGO_STATION_LENGTH = 3;
		local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
		local railType = AIRail.GetCurrentRailType();
		network = Network(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
	}

	function Start() {
		local cargoIDs = GenCargos();
		local cargo = cargoIDs.MAIL;
		local towns = AITownList();
		local town1 = towns.Begin();
		local town2 = towns.Next();

		Debug("stations in network.stations: ", network.stations.len());
		tasks.append(BuildRoadStopInTown(null, town1, cargo, network));
	}

	function Wake() {
		if (network != null) {
			Debug("stations in network.stations: ", network.stations.len());
		}
	}

}

class TransferNetwork extends Network {
	truck_stationA = null;
	truck_stationB = null;
	transfer_stationA = null;
	transfer_stationB = null;

	constructor(railType, trainLength, minDistance, maxDistance) {
		Network.constructor(railType, trainLength, minDistance, maxDistance);
	}
}

class TestTerminusStation extends Strategy {
	desc = "test terminus station";
	network = null;

	constructor() {
		local cargoIDs = GenCargos();
		local cargo = cargoIDs.MAIL;
		local CARGO_MIN_DISTANCE = 30;
		local CARGO_MAX_DISTANCE = 75;
		local CARGO_STATION_LENGTH = 4;
		local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
		local railType = AIRail.GetCurrentRailType();
		network = MixedNetwork(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
	}

	function Start() {
		local tilecount = AIMap.GetMapSize();
		local xtiles = AIMap.GetMapSizeX();
		local ytiles = AIMap.GetMapSizeY();
		local xcenter = xtiles / 2;
		local ycenter = ytiles / 2;
		local center = AIMap.GetTileIndex(xcenter, ycenter);
		local front =  AIMap.GetTileIndex(xcenter + 1, ycenter);

		local tiles = AITileList();
		SafeAddRectangle(tiles, center, 20);
		tiles.Valuate(AITile.IsBuildable);
		tiles.KeepValue(1);
		tiles.Valuate(AITile.GetSlope);
		tiles.KeepValue(AITile.SLOPE_FLAT);
		local site = tiles.Begin();
		local doubleTrack = true;

		local towns = AITownList();
		local town = towns.Begin();
		local direction = StationDirection(site, AITown.GetLocation(town));
		local platformLength = 4;

		local b = BuildTerminusStation(null, site, direction, network, town, doubleTrack, platformLength);
		b.Run();
		local t = TerminusStation.AtLocation(site, platformLength);
		local arr = t.GetEntrance();
		Debug("arr0 = ", arr[0], " arr1 = ", arr[1]);
		AISign.BuildSign(arr[0], "EN1");
		AISign.BuildSign(arr[1], "EN2");

		arr = t.GetExit();
		AISign.BuildSign(arr[0], "EX1");
		AISign.BuildSign(arr[1], "EX2");

		local loc = t.GetRoadDepot();
		Debug("loc=", loc);
		AISign.BuildSign(loc, "RD");

		loc = t.GetRoadDepotExit();
		Debug("loc=", loc);
		AISign.BuildSign(loc, "RX");

		loc = t.GetRailDepot();
		Debug("loc=", loc);
		AISign.BuildSign(loc, "DD");

		loc = t.GetRailDepotExit();
		Debug("loc=", loc);
		AISign.BuildSign(loc, "DE");
	}
}

class TestTransferStations extends Strategy {
	desc = "test building a station in a city, then a transfer station, finally link them";
	network = null;

	constructor() {
		local cargoIDs = GenCargos();
		local cargo = cargoIDs.MAIL;
		local CARGO_MIN_DISTANCE = 30;
		local CARGO_MAX_DISTANCE = 75;
		local CARGO_STATION_LENGTH = 4;
		local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
		local railType = AIRail.GetCurrentRailType();
		network = MixedNetwork(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
	}

	function Start() {
		local CARGO_STATION_LENGTH = 4;

		local cargoIDs = GenCargos();
		local cargo = cargoIDs.MAIL;
		local towns = AITownList();
		towns.Valuate(AITown.GetPopulation);
		towns.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		local townA = towns.Begin();
		local townB = towns.Next();
		local townA_loc = AITown.GetLocation(townA);
		local townB_loc = AITown.GetLocation(townB);

		tasks.append(BuildRoadStopInTown(null, townA, cargo, network));
		tasks.append(BuildTransferNearTown(null, townA, townB_loc, cargo, network));
		tasks.append(BuildRoadStopInTown(null, townB, cargo, network));
		tasks.append(BuildTransferNearTown(null, townB, townA_loc, cargo, network));
		RunTasks();

		local railstations = network.GetRailStations();
		Debug("railstations.len() is ", railstations.len());
		Debug("contents:");
		local r;
		foreach (r in railstations) {
			Debug("r is ", r);
		}

		local siteA = railstations[0];
		local siteB = railstations[1];
		local stationA = TerminusStation.AtLocation(siteA, CARGO_STATION_LENGTH);
		local stationB = TerminusStation.AtLocation(siteB, CARGO_STATION_LENGTH);
		/*
		local arr = stationA.GetEntrance();
		Debug("arr0 = ", arr[0], " arr1 = ", arr[1]);
		AISign.BuildSign(arr[0], "IN1");
		AISign.BuildSign(arr[1], "IN2");
		local arr2 = stationA.GetExit();
		AISign.BuildSign(arr2[0], "OUT1");
		AISign.BuildSign(arr2[1], "OUT2");
		local arr3 = stationA.GetRearEntrance();
		AISign.BuildSign(arr3[0], "RIN1");
		AISign.BuildSign(arr3[1], "RIN2");
		local arr4 = stationA.GetRearExit();
		AISign.BuildSign(arr4[0], "ROUT1");
		AISign.BuildSign(arr4[1], "ROUT2");

		Debug("siteB is ", siteB);
		arr = stationB.GetEntrance();
		Debug("arr0 = ", arr[0], " arr1 = ", arr[1]);
		AISign.BuildSign(arr[0], "IN1");
		AISign.BuildSign(arr[1], "IN2");
		arr2 = stationB.GetExit();
		AISign.BuildSign(arr2[0], "OUT1");
		AISign.BuildSign(arr2[1], "OUT2");
		arr3 = stationB.GetRearEntrance();
		AISign.BuildSign(arr3[0], "RIN1");
		AISign.BuildSign(arr3[1], "RIN2");
		arr4 = stationB.GetRearExit();
		AISign.BuildSign(arr4[0], "ROUT1");
		AISign.BuildSign(arr4[1], "ROUT2");
		*/

		local depotA = stationA.GetRailDepot();
		local depotB = stationB.GetRailDepot();
		local fromFlags = AIOrder.OF_NONE;
		local toFlags = fromFlags;

		tasks.extend([
			BuildTrack(null, stationA.GetExit(), stationB.GetEntrance(),
				[], SignalMode.FORWARD, network, BuildTrack.FAST),
			BuildTrack(null, stationB.GetExit(), stationA.GetEntrance(),
				[], SignalMode.FORWARD, network, BuildTrack.FOLLOW),
			BuildRoad(loc, stationface),
			BuildTrain2(siteA, siteB, depotA, depotB, network, fromFlags, toFlags, cargo)
		]);
		RunTasks();
	}

}
