function GetDescriptionForEvent(e) {
	switch (e.GetEventType()) {
		case AIEvent.ET_INVALID:
			return "ET_INVALID";
		case AIEvent.ET_TEST:
			return "ET_TEST";
		case AIEvent.ET_SUBSIDY_OFFER:
			return "ET_SUBSIDY_OFFER";
		case AIEvent.ET_SUBSIDY_OFFER_EXPIRED:
			return "ET_SUBSIDY_OFFER_EXPIRED";
		case AIEvent.ET_SUBSIDY_AWARDED:
			return "ET_SUBSIDY_AWARDED";
		case AIEvent.ET_SUBSIDY_EXPIRED:
			return "ET_SUBSIDY_EXPIRED";
		case AIEvent.ET_ENGINE_PREVIEW:
			return "ET_ENGINE_PREVIEW";
		case AIEvent.ET_COMPANY_NEW:
			return "ET_COMPANY_NEW";
		case AIEvent.ET_COMPANY_IN_TROUBLE:
			return "ET_COMPANY_IN_TROUBLE";
		case AIEvent.ET_COMPANY_ASK_MERGER:
			return "ET_COMPANY_ASK_MERGER";
		case AIEvent.ET_COMPANY_MERGER:
			return "ET_COMPANY_MERGER";
		case AIEvent.ET_COMPANY_BANKRUPT:
			return "ET_COMPANY_BANKRUPT";
		case AIEvent.ET_VEHICLE_CRASHED:
			return "ET_VEHICLE_CRASHED";
		case AIEvent.ET_VEHICLE_LOST:
			return "ET_VEHICLE_LOST";
		case AIEvent.ET_VEHICLE_WAITING_IN_DEPOT:
			return "ET_VEHICLE_WAITING_IN_DEPOT";
		case AIEvent.ET_VEHICLE_UNPROFITABLE:
			return "ET_VEHICLE_UNPROFITABLE";
		case AIEvent.ET_INDUSTRY_OPEN:
			return "ET_INDUSTRY_OPEN";
		case AIEvent.ET_INDUSTRY_CLOSE:
			return "ET_INDUSTRY_CLOSE";
		case AIEvent.ET_ENGINE_AVAILABLE:
			return "ET_ENGINE_AVAILABLE";
		case AIEvent.ET_STATION_FIRST_VEHICLE:
			return "ET_STATION_FIRST_VEHICLE";
		case AIEvent.ET_DISASTER_ZEPPELINER_CRASHED:
			return "ET_DISASTER_ZEPPELINER_CRASHED";
		case AIEvent.ET_DISASTER_ZEPPELINER_CLEARED:
			return "ET_DISASTER_ZEPPELINER_CLEARED";
		case AIEvent.ET_TOWN_FOUNDED:
			return "ET_TOWN_FOUNDED";
		case AIEvent.ET_AIRCRAFT_DEST_TOO_FAR:
			return "ET_AIRCRAFT_DEST_TOO_FAR";
		case AIEvent.ET_ADMIN_PORT:
			return "ET_ADMIN_PORT";
		case AIEvent.ET_WINDOW_WIDGET_CLICK:
			return "ET_WINDOW_WIDGET_CLICK";
		case AIEvent.ET_GOAL_QUESTION_ANSWER:
			return "ET_GOAL_QUESTION_ANSWER";
		case AIEvent.ET_EXCLUSIVE_TRANSPORT_RIGHTS:
			return "ET_EXCLUSIVE_TRANSPORT_RIGHTS";
		case AIEvent.ET_ROAD_RECONSTRUCTION:
			return "ET_ROAD_RECONSTRUCTION";
		case AIEvent.ET_VEHICLE_AUTOREPLACED:
			return "ET_VEHICLE_AUTOREPLACED";
		case AIEvent.ET_STORYPAGE_BUTTON_CLICK:
			return "ET_STORYPAGE_BUTTON_CLICK";
		case AIEvent.ET_STORYPAGE_TILE_SELECT:
			return "ET_STORYPAGE_TILE_SELECT";
		case AIEvent.ET_STORYPAGE_VEHICLE_SELECT:
			return "ET_STORYPAGE_VEHICLE_SELECT";
		default:
			return "unknown event";
	}
}

function GetRating(stationID, cargo) {
	local rating = 100;
	local sname = AIStation.GetName(stationID);
	if (AIStation.HasCargoRating(stationID, cargo)) {
		rating = AIStation.GetCargoRating(stationID, cargo);
		//Debug("rating at ", sname, " station is ", rating);
	} else {
		//Debug("station ", sname, " has no rating");
	}
	return rating;
}

function GetBetweenTown(loc_a, loc_b)
{
	local town1 = AITile.GetClosestTown(loc_a);
	local town2 = AITile.GetClosestTown(loc_b);
	if (town1 == town2) {
		return town1;
	}
	return null;
}

function AllocateTruck(cargo) {
	local z = 0;
	local ctl = AICargo.GetCargoLabel(cargo);
	Debug("Pick truck for " + ctl);

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
	Debug("Chose", AIEngine.GetName(eID));
	return eID;
}

function FindIndustryStation(id) {
	Debug("FIND station location for ", info.name, " at ", info.loc);
	local first, tiles;
	local itype = AIIndustry.GetIndustryType(info.id);
	local prodlist = AIIndustryType.GetProducedCargo(itype);
	local acclist = AIIndustryType.GetAcceptedCargo(itype);

	local radius = 10;
	if (prodlist.HasItem(this.cargo)) {
		tiles = AITileList_IndustryProducing(info.id, radius);
		Debug(info.name, " produces ", AICargo.GetCargoLabel(this.cargo));
	} else if (acclist.HasItem(this.cargo)) {
		tiles = AITileList_IndustryAccepting(info.id, radius);
		Debug(info.name, " accepts ", AICargo.GetCargoLabel(this.cargo));
	}

	Debug("AITileList() count=", tiles.Count());
	//SafeAddRectangle(tiles, info.loc, radius);
	//Debug("SafeAddRectangle count=", tiles.Count());
	tiles.Valuate(AITile.IsBuildableRectangle, 2, 2);
	tiles.KeepValue(1);
	Debug("IsBuildableRectangle", tiles.Count());

	tiles.Valuate(AITile.GetSlope);
	tiles.KeepValue(AITile.SLOPE_FLAT);
	Debug("AITile.GetSlope", tiles.Count());

	tiles.Valuate(AITile.GetDistanceManhattanToTile, info.loc);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

	first = tiles.Begin();
	/*
	local t;
	for (t = first; !tiles.IsEnd(); t = tiles.Next())
	{
		//AISign.BuildSign(t, "X");
	}
	*/
	return first;
}

// ttype AITile.TRANSPORT_ROAD, TRANSPORT_RAIL, TRANSPORT_WATER, TRANSPORT_AIR, 
function FindClosestDepot(location, ttype=AITile.TRANSPORT_ROAD, distance=20) {
	local dlist = AIDepotList(ttype);
	dlist.Valuate(AITile.GetDistanceManhattanToTile, location);
	dlist.KeepBelowValue(distance);
	dlist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	if (dlist.Count() > 0) {
		return dlist.Begin();
	}
	return null;
}

function IsIndustryInTown(industry) {
	if (!AIIndustry.IsValidIndustry(industry)) {
		Debug("industry ", industry, " not valid");
		return null;
	}
	local iloc = AIIndustry.GetLocation(industry);
	local iname = AIIndustry.GetName(industry);
	Debug("industry is ", iname);

	local townID = AITile.GetTownAuthority(iloc);
	if (!AITown.IsValidTown(townID)) {
		Debug("town ", townID, " not valid.  Trying again");
		townID = AITile.GetClosestTown(iloc);
		if (!AITown.IsValidTown(townID)) {
			Debug("town ", townID, " not valid");
			return null;
		}
	}

	local tname = AITown.GetName(townID);
	if (!AITile.IsWithinTownInfluence(iloc, townID)) {
		Debug("industry ", iname, " is not in the jurisdiction of the town of ", tname);
		return false;
	}

	local townloc = AITown.GetLocation(townID);
	local dist = AITile.GetDistanceManhattanToTile(townloc, iloc);
	Debug("townloc=", townloc, " tname=", tname, " dist=", dist);
	local tiles = AITileList();
	SafeAddRectangle(tiles, townloc, dist);
	Debug("tile count is ", tiles.Count());
	tiles.Valuate(AITile.GetTownAuthority);
	tiles.KeepValue(townID);
	Debug("tile count is ", tiles.Count());
	tiles.Valuate(AITile.IsWaterTile);
	tiles.KeepValue(0);
	Debug("tile count is ", tiles.Count());
	if (tiles.Count() > 0) {
		local t;
		foreach (t,_ in tiles) {
			//Debug("t is ", t);
			AISign.BuildSign(t, "X");
		}
	}

	return false;

}

function GenCargos()
{
	/*
	in some scenarios these are the cargos:
	cargoIDs = {
		VALU=10,
		STEL=9,
		IORE=8,
		WOOD=7,
		GRAI=6,
		GOOD=5,
		LVST=4,
		OIL_=3,
		MAIL=2,
		COAL=1,
		PASS=0,
	}
	*/
	local cargoIDs = {};

	local clist = AICargoList();
	local cname, cID, z;
	local debugstr = "cargo mappings:";
	foreach (cID,z in clist) {
		cname = AICargo.GetCargoLabel(cID);
		cargoIDs[cname] <- cID;
		//Debug(cname + "=" + cID);
		debugstr += " " + cname + "=" + cID;
	}
	Debug(debugstr);
	return cargoIDs;
}

function Debug(...) {
	local s = "";
	for(local i = 0; i< vargc; i++) {
		s = s + " " + vargv[i];
	}
	
	AILog.Info(GetDate() + ":" + s);
}

function Warning(...) {
	local s = "";
	for(local i = 0; i< vargc; i++) {
		s = s + " " + vargv[i];
	}
	
	AILog.Warning(GetDate() + ":" + s);
}

function Error(...) {
	local s = "";
	for(local i = 0; i< vargc; i++) {
		s = s + " " + vargv[i];
	}
	
	AILog.Error(GetDate() + ":" + s);
}

function GetDate() {
	local date = AIDate.GetCurrentDate();
	return "" + AIDate.GetYear(date) + "-" + ZeroPad(AIDate.GetMonth(date)) + "-" + ZeroPad(AIDate.GetDayOfMonth(date));
}

function PrintError(ret=false) {
	if (ret != true) {
		Error(AIError.GetLastErrorString());
	}
}


function Sign(x) {
	if (x < 0) return -1;
	if (x > 0) return 1;
	return 0;
}

/**
 * Calculates an integer square root.
 */
function Sqrt(i) {
	if (i == 0)
		return 0;   // Avoid divide by zero
	local n = (i / 2) + 1;       // Initial estimate, never low
	local n1 = (n + (i / n)) / 2;
	while (n1 < n) {
		n = n1;
		n1 = (n + (i / n)) / 2;
	}
	return n;
}

function Min(a, b) {
	return a < b ? a : b;
}

function Range(from, to) {
	local range = [];
	for (local i=from; i<to; i++) {
		range.append(i);
	}
	
	return range;
}

/**
 * Return the closest integer equal to or greater than x.
 */
function Ceiling(x) {
	if (x.tointeger().tofloat() == x) return x.tointeger();
	return x.tointeger() + 1;
}

function RandomTile() {
	return abs(AIBase.Rand()) % AIMap.GetMapSize();
}

/**
 * Sum up the values of an AIList.
 */
function Sum(list) {
	local sum = 0;
	for (local item = list.Begin(); list.IsEnd(); item = list.Next()) {
		sum += list.GetValue(item);
	}
	
	return sum;
}

/**
 * Create a string of all elements of an array, separated by a comma.
 */
function ArrayToString(a) {
	if (a == null) return "";
	
	local s = "";
	foreach (index, item in a) {
		if (index > 0) s += ", ";
		s += item;
	}
	
	return s;
}

/**
 * Turn a tile index into an "x, y" string.
 */
function TileToString(tile) {
	return "(" + AIMap.GetTileX(tile) + ", " + AIMap.GetTileY(tile) + ")";
}

/**
 * Concatenate the same string, n times.
 */
function StringN(s, n) {
	local r = "";
	for (local i=0; i<n; i++) {
		r += s;
	}
	
	return r;
}

function ZeroPad(i) {
	return i < 10 ? "0" + i : "" + i;
}

function StartsWith(a, b) {
	return a.find(b) == 0;
}

/**
 * Swap two tiles - used for swapping entrance/exit tile strips.
 */
function Swap(tiles) {
	return [tiles[1], tiles[0]];
}

/**
 * Create an array from an AIList.
 */
function ListToArray(l) {
	local a = [];
	for (local item = l.Begin(); !l.IsEnd(); item = l.Next()) a.append(item);
	return a;
}

/**
 * Create an AIList from an array.
 */
function ArrayToList(a) {
	local l = AIList();
	foreach (item in a) l.AddItem(item, 0);
	return l;
}

/**
 * Return an array that contains all elements of a and b.
 */
function Concat(a, b) {
	local r = [];
	r.extend(a);
	r.extend(b);
	return r;
}

/**
 * Add a rectangular area to an AITileList containing tiles that are within /radius/
 * tiles from the center tile, taking the edges of the map into account.
 */  
function SafeAddRectangle(list, tile, xradius, yradius=null) {
	if (yradius == null) { yradius = xradius }
	local x1 = max(0, AIMap.GetTileX(tile) - xradius);
	local y1 = max(0, AIMap.GetTileY(tile) - yradius);
	
	local x2 = min(AIMap.GetMapSizeX() - 2, AIMap.GetTileX(tile) + xradius);
	local y2 = min(AIMap.GetMapSizeY() - 2, AIMap.GetTileY(tile) + yradius);

	//Debug("x1=", x1, " y1=", y1, " x2=", x2, " y2=", y2);
	if (x1 < 1) { x1 = 1 }
	if (x2 < 1) { x2 = 1 }
	if (y1 < 1) { y1 = 1 }
	if (y2 < 1) { y2 = 1 }
	
	list.AddRectangle(AIMap.GetTileIndex(x1, y1),AIMap.GetTileIndex(x2, y2)); 
}

/**
 * Filter an AITileList for AITile.IsBuildable tiles.
 */
function KeepBuildableArea(area) {
	area.Valuate(AITile.IsBuildable);
	area.KeepValue(1);
	return area;
}

function InverseDirection(direction) {
	switch (direction) {
		case Direction.N: return Direction.S;
		case Direction.E: return Direction.W;
		case Direction.S: return Direction.N;
		case Direction.W: return Direction.E;
		
		case Direction.NE: return Direction.SW;
		case Direction.SE: return Direction.NW;
		case Direction.SW: return Direction.NE;
		case Direction.NW: return Direction.SE;
		default: throw "invalid direction";
	}
}

function DirectionName(direction) {
	switch (direction) {
		case Direction.N: return "N";
		case Direction.E: return "E";
		case Direction.S: return "S";
		case Direction.W: return "W";
		
		case Direction.NE: return "NE";
		case Direction.SE: return "SE";
		case Direction.SW: return "SW";
		case Direction.NW: return "NW";
		default: throw "invalid direction";
	}
}

/**
 * Find the cargo ID for passengers.
 * Otto: newgrf can have tourist (TOUR) which qualify as passengers but townfolk won't enter the touristbus...
 * hence this rewrite; you can check for PASS as string, but this is discouraged on the wiki
 */
function GetPassengerCargoID() {
	return GetCargoID(AICargo.CC_PASSENGERS);
}

function GetMailCargoID() {
	return GetCargoID(AICargo.CC_MAIL);
}

function GetCargoID(cargoClass) {
	local list = AICargoList();
	local candidate = -1;
	local i;
	foreach (i,j in list) {
		if (AICargo.HasCargoClass(i, cargoClass)) {
			candidate = i;
		}
	}
	
	if(candidate != -1)
		return candidate;
	
	throw "missing required cargo class";
}

function GetMaxBridgeLength() {
	local length = AIController.GetSetting("MaxBridgeLength");
	while (length > 0 && AIBridgeList_Length(length).IsEmpty()) {
		length--;
	}
	
	return length;
}

function GetMaxBridgeCost(length) {
	local bridges = AIBridgeList_Length(length);
	if (bridges.IsEmpty()) throw "Cannot build " + length + " tile bridges!";
	bridges.Valuate(AIBridge.GetMaxSpeed);
	bridges.KeepTop(1);
	local bridge = bridges.Begin();
	return AIBridge.GetPrice(bridge, length);
}

function TrainLength(train) {
	// train length in tiles
	return (AIVehicle.GetLength(train) + 15) / 16;
}

function HaveHQ() {
	return AICompany.GetCompanyHQ(COMPANY) != AIMap.TILE_INVALID;
}

function GetEngine(cargo, railType, bannedEngines, cheap) {
	local engineList = AIEngineList(AIVehicle.VT_RAIL);
	engineList.Valuate(AIEngine.IsWagon);
	engineList.KeepValue(0);
	engineList.Valuate(AIEngine.CanRunOnRail, railType);
	engineList.KeepValue(1);
	engineList.Valuate(AIEngine.HasPowerOnRail, railType);
	engineList.KeepValue(1);
	engineList.Valuate(AIEngine.CanPullCargo, cargo);
	engineList.KeepValue(1);
	engineList.RemoveList(ArrayToList(bannedEngines));
	
	engineList.Valuate(AIEngine.GetPrice);
	if (cheap) {
		// go for the cheapest
		engineList.KeepBottom(1);
	} else {
		// pick something middle of the range, by removing the top half
		// this will hopefully give us something decent, even when faced with newgrf train sets
		engineList.Sort(AIList.SORT_BY_VALUE, true);
		engineList.RemoveTop(engineList.Count() / 2);
	}
	
	if (engineList.IsEmpty()) throw TaskFailedException("no suitable engine");
	return engineList.Begin();
}

function GetWagon(cargo, railType) {
	// select the largest appropriate wagon type
	local engineList = AIEngineList(AIVehicle.VT_RAIL);
	engineList.Valuate(AIEngine.CanRefitCargo, cargo);
	engineList.KeepValue(1);
	engineList.Valuate(AIEngine.IsWagon);
	engineList.KeepValue(1);
	
	engineList.Valuate(AIEngine.CanRunOnRail, railType);
	engineList.KeepValue(1);
	
	// prefer engines that can carry this cargo without a refit,
	// because their refitted capacity may be different from
	// their "native" capacity - for example, NARS Ore Hoppers
	local native = AIList();
	native.AddList(engineList);
	native.Valuate(AIEngine.GetCargoType);
	native.KeepValue(cargo);
	if (!native.IsEmpty()) {
		engineList = native;
	}
	
	engineList.Valuate(AIEngine.GetCapacity)
	engineList.KeepTop(1);
	
	if (engineList.IsEmpty()) throw TaskFailedException("no suitable wagon");
	return engineList.Begin();
}

function MaxDistance(cargo, trainLength) {
	// maximum safe rail distance we can expect to build with our starting loan
	local rail = AIRail.GetCurrentRailType();
	local engine = GetEngine(cargo, rail, [], true);
	local wagon = GetWagon(cargo, rail);
	local trainCost = AIEngine.GetPrice(engine) + AIEngine.GetPrice(wagon) * (trainLength-1) * 2;
	local bridgeCost = GetMaxBridgeCost(GetMaxBridgeLength());
	local tileCost = AIRail.GetBuildCost(rail, AIRail.BT_TRACK);
	return (AICompany.GetMaxLoanAmount() - trainCost - bridgeCost) / tileCost;
}

function GetGameSetting(setting, defaultValue) {
	return AIGameSettings.IsValid(setting) ? AIGameSettings.GetValue(setting) : defaultValue;
}

class Counter {
	
	count = 0;
	
	constructor() {
		count = 0;
	}
	
	function Get() {
		return count;
	}
	
	function Inc() {
		count++;
	}
}

/**
 * A boolean flag, usable as a static field.
 */
class Flag {
	
	value = null;
	
	constructor() {
		value = false;
	}
	
	function Set(value) {
		this.value = value;
	}
	
	function Get() {
		return value;
	}
}
