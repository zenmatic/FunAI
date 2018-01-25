class RelativeCoordinates {
	
	static matrices = [
		// ROT_0
		[ 1, 0,
		  0, 1],

		// ROT_90
		[ 0,-1,
		  1, 0],

		// ROT_180
		[-1, 0,
		  0,-1],

		// ROT_270
		[ 0, 1,
		 -1, 0]
	];
	
	location = null;
	rotation = null;	
	
	constructor(location, rotation = Rotation.ROT_0) {
		this.location = location;
		this.rotation = rotation;
	}
	
	function GetTile(coordinates) {
		local matrix = matrices[rotation];
		local x = coordinates[0] * matrix[0] + coordinates[1] * matrix[1];
		local y = coordinates[0] * matrix[2] + coordinates[1] * matrix[3];
		//Debug(coordinates[0] + "," + coordinates[1] + " -> " + x + "," + y);
		local new = location + AIMap.GetTileIndex(x, y);
		//Debug(location, " becomes ", new);
		return new;
	}
	
}

class WorldObject {
	
	relativeCoordinates = null;
	location = null;
	rotation = null;
	
	constructor(location, rotation = Rotation.ROT_0) {
		this.relativeCoordinates = RelativeCoordinates(location, rotation);
		this.location = location;
		this.rotation = rotation;
	}
	
	function GetTile(coordinates) {
		return relativeCoordinates.GetTile(coordinates);
	}
	
	function TileStrip(start, end) {
		local tiles = [];
		
		local count, xstep, ystep;
		if (start[0] == end[0]) {
			count = abs(end[1] - start[1]);
			xstep = 0;
			ystep = end[1] < start[1] ? -1 : 1;
		} else {
			count = abs(end[0] - start[0]);
			xstep = end[0] < start[0] ? -1 : 1;
			ystep = 0
		}
		
		for (local i = 0, x  = start[0], y = start[1]; i <= count; i++, x += xstep, y += ystep) {
			tiles.append(GetTile([x, y]));
		}
				
		return tiles;
	}
}

class Crossing extends WorldObject {
	
	static WIDTH = 4;
	
	constructor(location) {
		WorldObject.constructor(location);
	}
	
	function GetEntrance(direction) {
		local a, b;
		
		switch (direction) {
			case Direction.NE: a = [-1, 1]; b = [0,1]; break;
			case Direction.SE: a = [ 1, 4]; b = [1,3]; break;
			case Direction.SW: a = [ 4, 2]; b = [3,2]; break;
			case Direction.NW: a = [ 2,-1]; b = [2,0]; break;
			default: throw "Invalid direction";
		}
		
		return TileStrip(a, b);
	}
	
	function GetExit(direction) {
		local a, b;
		
		switch (direction) {
			case Direction.NE: a = [0,2]; b = [-1, 2]; break;
			case Direction.SE: a = [2,3]; b = [ 2, 4]; break;
			case Direction.SW: a = [3,1]; b = [ 4, 1]; break;
			case Direction.NW: a = [1,0]; b = [ 1,-1]; break;
			default: throw "Invalid direction";
		}
		
		return TileStrip(a, b);
	}
	
	function GetReservedEntranceSpace(direction) {
		local a, b;
		
		switch (direction) {
			case Direction.NE: a = [-5, 1]; b = [0,1]; break;
			case Direction.SE: a = [ 1, 8]; b = [1,3]; break;
			case Direction.SW: a = [ 8, 2]; b = [3,2]; break;
			case Direction.NW: a = [ 2,-5]; b = [2,0]; break;
			default: throw "Invalid direction";
		}
		
		return TileStrip(a, b);
	}

	function GetReservedExitSpace(direction) {
		local a, b;
		
		switch (direction) {
			case Direction.NE: a = [0,2]; b = [-5, 2]; break;
			case Direction.SE: a = [2,3]; b = [ 2, 8]; break;
			case Direction.SW: a = [3,1]; b = [ 8, 1]; break;
			case Direction.NW: a = [1,0]; b = [ 1,-5]; break;
			default: throw "Invalid direction";
		}
		
		return TileStrip(a, b);
	}
	
	function CountConnections() {
		local count = 0;
		
		local exits = [
			GetExit(Direction.NE),
			GetExit(Direction.SE),
			GetExit(Direction.SW),
			GetExit(Direction.NW),
		];
		
		foreach (exit in exits) {
			// TODO: this may be incorrect if another track runs right past the crossing
			if (AITile.GetOwner(exit[1]) == COMPANY && AIRail.IsRailTile(exit[1])) {
				count++;
			}
		}
		
		return count;
	}
	
	function GetName() {
		local waypoints = [ [0,0], [0,2], [2,3], [3,1], [1,0] ];
		foreach (tile in waypoints) {
			local waypoint = AIWaypoint.GetWaypointID(GetTile(tile));
			if (AIWaypoint.IsValidWaypoint(waypoint)) {
				return AIWaypoint.GetName(waypoint);
			}
		}
		
		return "unnamed junction at " + TileToString(location);
	}
	
	function _tostring() {
		return GetName();
	}
	
}

class TerminusStation extends WorldObject {
	
	platformLength = null;
	location = null;
	
	constructor(location, rotation, platformLength) {
		WorldObject.constructor(location, rotation);
		this.platformLength = platformLength;
	}
	
	function AtLocation(location, platformLength) {
		// deduce the rotation of an existing station
		local rotation;
		local direction = AIRail.GetRailStationDirection(location);
		if (direction == AIRail.RAILTRACK_NE_SW) {
			if (AIRail.IsRailStationTile(location + AIMap.GetTileIndex(1,0))) {
				rotation = Rotation.ROT_270;
				Debug("rotation = Rotation.ROT_270");
			} else {
				rotation = Rotation.ROT_90;
				Debug("rotation = Rotation.ROT_90");
			}
		} else if (direction == AIRail.RAILTRACK_NW_SE) {
			if (AIRail.IsRailStationTile(location + AIMap.GetTileIndex(0,1))) {
				rotation = Rotation.ROT_0;
				Debug("rotation = Rotation.ROT_0");
			} else {
				rotation = Rotation.ROT_180;
				Debug("rotation = Rotation.ROT_180");
			}
		} else {
			throw "no station at " + location;
		}
		
		return TerminusStation(location, rotation, platformLength);
	}
	
	function _tostring() {
		return AIStation.GetName(AIStation.GetStationID(location));
	}
	
	function GetEntrance() {
		return TileStrip([0, platformLength + 2], [0, platformLength + 1]);
	}
	
	function GetExit() {
		return TileStrip([1, platformLength + 1], [1, platformLength + 2]);
	}
	
	function GetReservedEntranceSpace() {
		return TileStrip([0, platformLength], [0, platformLength + 2]);
	}

	function GetReservedExitSpace() {
		return TileStrip([1, platformLength], [1, platformLength + 2]);
	}
	
	function GetRearEntrance() {
		return TileStrip([1, -1], [1, 0]);
	}
	
	function GetRearExit() {
		return TileStrip([0, 0], [0, -1]);
	}
	
	function GetReservedRearEntranceSpace() {
		return TileStrip([1, -1], [1, -2]);
	}

	function GetReservedRearExitSpace() {
		return TileStrip([0, 0], [0, -2]);
	}
	
	function GetRoadDepot() {
		return GetTile([2,3]);
	}
	
	function GetRoadDepotExit() {
		return GetTile([2,2]);
	}

	function GetRailDepot() {
		return GetTile([2,4]);
	}

	function GetRailDepotExit() {
		return GetTile([1,4]);
	}
}

class Network {
	
	railType = null;
	trainLength = null;
	minDistance = null;
	maxDistance = null;
	stations = null;
	depots = null;
	trains = null;
	
	constructor(railType, trainLength, minDistance, maxDistance) {
		this.railType = railType;
		this.trainLength = trainLength;
		this.minDistance = minDistance;
		this.maxDistance = maxDistance;
		this.stations = [];
		this.depots = [];
		this.trains = [];
	}
	
}

class MixedNetwork extends Network {

	function GetStations(stype=AIStation.STATION_TRAIN) {
		local arr = [];
		local stationID, tile;
		if (stations.len() > 0) {
			foreach (tile in stations) {
				stationID = AIStation.GetStationID(tile);
				if (AIStation.HasStationType(stationID, stype)) {
					arr.append(tile);
				}
			}
		}
		return arr;
	}

	function GetRailStations() {
		return GetStations();
	}

	function GetBusStations() {
		return GetStations(AIStation.STATION_BUS_STOP);
	}

	function GetTruckStations() {
		return GetStations(AIStation.STATION_TRUCK_STOP);
	}

	function GetRoadStations() {
		local arr1 = GetBusStations();
		local arr2 = GetTruckStations();
		arr1.extend(arr2);
		return arr1;
	}

	function GetDepots(ttype=AITile.TRANSPORT_RAIL) {
		local func, depot, arr = [];

		if (ttype == AITile.TRANSPORT_RAIL) {
			func = AIRail.IsRailDepotTile;
		} else if (ttype == AITile.TRANSPORT_ROAD) {
			func = AIRoad.IsRoadDepotTile;
		} else if (ttype == AITile.TRANSPORT_WATER) {
			// TODO
			func = null;
		} else if (ttype == AITile.TRANSPORT_AIR) {
			// TODO
			func = null;
		} else {
			return null;
		}

		foreach (loc in depots) {
			if (func(depot)) {
				arr.append(depot);
			}
		}
		return arr;
	}

	function GetRailDepots() {
		return GetDepots();
	}

	function GetRoadDepots() {
		return GetDepots(AITile.TRANSPORT_ROAD);
	}

	function GetWaterDepots() {
		return GetDepots(AITile.TRANSPORT_WATER);
	}

	function GetAirDepots() {
		return GetDepots(AITile.TRANSPORT_AIR);
	}

}

class WorldTiles {
	checks = null;
	totaltiles = 0;

	constructor() {
		this.totaltiles = AIMap.GetMapSize();
		this.checks = {
			water = {
				func = AITile.IsWaterTile,
				count = 0,
				percent = 0,
			},
			land = {
				func = IsLandTile,
				count = 0,
				percent = 0,
			},
		};

		Update();
	}

	function GetCount(tiletype) {
		try {
			return this.checks[tiletype].count;
		} catch (e) {
			Debug("tiletype ", tiletype, " doesn't exist");
			return null;
		}
	}

	function GetPercentage(tiletype) {
		try {
			return this.checks[tiletype].percent;
		} catch (e) {
			Debug("tiletype ", tiletype, " doesn't exist");
			return null;
		}
	}

	function GetAllCounts() {
		return this.checks;
	}

	function Update() {

		local x = 1;
		local y = 1;
		local first = AIMap.GetTileIndex(x,y)

		x = AIMap.GetMapSizeX();
		y = AIMap.GetMapSizeY();
		local last = AIMap.GetTileIndex(x,y);

		local tiles = AITileList();
		tiles.AddRectangle(first, last)

		local tiletype, tbl;
		foreach (tiletype,tbl in checks) {
			local tlist = tiles;
			tlist.Valuate(tbl.func);
			tlist.KeepValue(1);
			local ct = tlist.Count();
			local percent = (ct / this.totaltiles) * 100;
			this.checks[tiletype].count = ct;
			this.checks[tiletype].percent = percent;
			Debug(tiletype, " count=", ct, " percent=", percent);
		}
	}

	
	function IsLandTile(tile) {
		if (AITile.IsWaterTile(tile) || AITile.IsCoastTile(tile)) {
			return false;
		}
		return true;
	}
}
