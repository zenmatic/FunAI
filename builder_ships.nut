class BuildDock extends Task {

	RADIUS = 40;
	location = null;
	dock = null;

	constructor(parentTask, loc) {
		Task.constructor(parentTask, null);
		location = loc;
	}

	function _tostring() {
		return "BuildDock";
	}

	function Run() {
		local tiles = AITileList();
		SafeAddRectangle(tiles, this.location, this.RADIUS);
		tiles.Valuate(AITile.IsCoastTile);
		tiles.KeepValue(1);

		tiles.Valuate(AITile.GetDistanceManhattanToTile, this.location);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		if (tiles.Count() < 1) {
			throw TaskFailedException("no suitable tiles for a dock in " + this.RADIUS + " radius");
		}

		local tile;
		foreach (tile,_ in tiles) {
			if (AIMarine.BuildDock(tile, AIStation.STATION_NEW)) {
				this.dock = tile;
				return;
			}
		}
		throw TaskFailedException("unable to build dock");
	}
}

class BuildShipRoute extends Task {

	depot = null;
	producer = null;
	consumer = null;
	cargo = null;

	constructor(parentTask, the_depot, producer_loc, consumer_loc, cargoID) {
		Task.constructor(parentTask, null);
		producer = producer_loc;
		consumer = consumer_loc;
		depot = the_depot;
		cargo = cargoID;
	}

	function _tostring() {
		return "BuildShipRoute";
	}
	
	function Run() {
		local ships = AIEngineList(AIVehicle.VT_WATER);
		ships.Valuate(AIEngine.IsBuildable);
		ships.KeepValue(1);
		ships.Valuate(AIEngine.CanRefitCargo, cargo);
		ships.KeepValue(1);
		if (ships.Count() < 1) {
			Debug("no ships available");
			throw TaskRetryException();
		}

		local ship = ships.Begin();
		local shipID = AIVehicle.BuildVehicle(depot, ship);
		AIVehicle.RefitVehicle(shipID, cargo);

		local flags = AIOrder.OF_NONE;
		AIOrder.AppendOrder(shipID, producer, flags);
		AIOrder.AppendOrder(shipID, consumer, flags);
		AIOrder.AppendOrder(shipID, depot, flags);
		AIVehicle.StartStopVehicle(shipID);
	}
}

class BuildWaterDepotBetween extends Task {

	location1 = null;
	location2 = null;
	midpoint = null;
	ATTEMPT_RADIUS = 15;
	depot = null;

	constructor(parentTask, loc1, loc2) {
		Task.constructor(parentTask, null);
		location1 = loc1;
		location2 = loc2;
		midpoint = PointBetween(loc1, loc2);
	}

	function _tostring() {
		return "BuildWaterDepotBetween";
	}

	function Run() {

		local tiles = AITileList();
		SafeAddRectangle(tiles, this.midpoint, this.ATTEMPT_RADIUS);
		tiles.Valuate(AITile.IsWaterTile);
		tiles.KeepValue(1);

		tiles.Valuate(AITile.GetDistanceManhattanToTile, this.midpoint);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		local tile;
		foreach (tile,_ in tiles) {
			local area = AITileList();
			SafeAddRectangle(area, tile, 1);
			local front;
			foreach (front,_ in area) {
				if (AIMarine.BuildWaterDepot(tile, front)) {
					Debug("water depot built at ", tile);
					this.depot = tile;
					return;
				}
			}
		}
		throw TaskFailedException("unable to build water depot");
	}

	function PointBetween(loc1, loc2) {
		local x1 = AIMap.GetTileX(loc1);
		local y1 = AIMap.GetTileY(loc1);
		local x2 = AIMap.GetTileX(loc2);
		local y2 = AIMap.GetTileY(loc2);

		local midx = (x1 + x2) / 2;
		local midy = (y1 + y2) / 2;
		local tile = AIMap.GetTileIndex(midx, midy);

		return tile;
	}
}
