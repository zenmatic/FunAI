class BuildStopInTown extends Task {

	townID = null;
	cargo = null;
	station = null;

	constructor(parentTask, townID, cargo) {
		Task.constructor(parentTask, null);
		this.townID = townID;
		this.cargo = cargo;
	}

	function _tostring() {
		return "BuildStopInTown";
	}

	function Run() {

		local stat = AIStation.STATION_NEW;
		local ctn = AICargo.GetCargoLabel(cargo);
		local stype = AIRoad.GetRoadVehicleTypeForCargo(cargo);
		local stoptype = "UNKNOWN";
		if (stype == AIRoad.ROADVEHTYPE_BUS) {
			stoptype = "bus";
		} else if (stype == AIRoad.ROADVEHTYPE_TRUCK) {
			stoptype = "truck";
		}
		Debug("build " + stoptype + " stop for " + ctn + " cargo (" +
			cargo + ") in " + AITown.GetName(townID));

		local printvals = function(arr, msg) {
			Debug(msg, ":", arr.Count());
		}

		local maxRange = Sqrt(AITown.GetPopulation(townID)/100) + 4; 
		local tiles = AITileList();
		SafeAddRectangle(tiles, AITown.GetLocation(townID), maxRange);
		printvals(tiles, "AITileList()");

		//tiles.Valuate(AITown.IsWithinTownInfluence, townID);
		//tiles.KeepValue(1);
		//printvals(tiles, "AITile.IsWithinTownInfluence");

		//tiles.Valuate(AITile.HasTransportType, AITile.TRANSPORT_ROAD);
		tiles.Valuate(AIRoad.IsRoadTile);
		tiles.KeepValue(1);
		printvals(tiles, "AIRoad.IsRoadTile");

		tiles.Valuate(AITile.GetCargoAcceptance, cargo, 1, 1, 1);
		tiles.KeepAboveValue(1);
		printvals(tiles, "AITile.GetCargoAcceptance");

		tiles.Valuate(AITile.GetDistanceManhattanToTile, AITown.GetLocation(townID));
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		/* find buildable spots along the road */
		local t, sur, s, z, ret;
		foreach (t,z in tiles) {
			sur = AITileList();
			SafeAddRectangle(sur, t, 1);

			sur.Valuate(AIRoad.IsRoadTile);
			sur.KeepValue(1);
			foreach (s,z in sur) {
				ret = AIRoad.BuildDriveThroughRoadStation(t,s,stype,stat);
				if (ret) {
					// pass this to the parent?
					//info.roadstation <- AIStation.GetStationID(t);
					this.station = t;
					return;
				}
			}
		}
		throw TaskFailedException("no place to build a " + stoptype + " station");
	}
}

class BuildTruckRoute extends Task {

	producer = null;
	consumer = null;
	cargo = null;
	vgroup = null;

	constructor(parentTask, prod, cons, cargoID) {
		Task.constructor(parentTask, null);
		producer = prod;
		consumer = cons;
		cargo = cargoID;
		vgroup = AIGroup.CreateGroup(AIVehicle.VT_ROAD);
		subtasks = [];
	}
	
	function _tostring() {
		return "BuildTruckRoute";
	}
	
	function Run() {

		local depot = FindClosestDepot(producer, AITile.TRANSPORT_ROAD);
		if (depot == null) {
			local d = BuildTruckDepot(this, producer);
			d.Run();
			depot = d.depot;
			if (depot == null) {
				throw TaskFailedException("unable to build depot");
			}
		}
		Debug("depot is ", depot);
		local pobj = BuildTruckStation(this, producer);
		local cobj = BuildTruckStation(this, consumer);
		subtasks.extend([
			pobj,
			cobj,
		]);
		RunSubtasks();
		Debug("pobj.station is ", pobj.station, " cobj.station is ", cobj.station);
		if (pobj.station == null) {
			throw TaskFailedException("pobj.station is null");
		} else if (cobj.station == null) {
			throw TaskFailedException("cobj.station is null");
		}

		subtasks.extend([
			BuildTruckRoad(this, pobj.station, depot),
		]);

		local town = GetBetweenTown(pobj.station, cobj.station);
		if (town != null) {
			local town_loc = AITown.GetLocation(town);
			subtasks.extend([
				BuildTruckRoad(this, pobj.station, town_loc),
				BuildTruckRoad(this, cobj.station, town_loc),
			]);
		} else {
			subtasks.append(BuildTruckRoad(this, cobj.station, pobj.station));
		}
		subtasks.append(BuildTruck(this, depot, pobj.station, cobj.station, cargo));
		RunSubtasks();
	}
}

//class BuildTruckRoad extends Task {
//	location1 = null;
//	location2 = null;
//	MAX_TRIES = 100;
//
//	constructor(parentTask, loc1, loc2) {
//		Task.constructor(parentTask, null);
//		this.location1 = loc1;
//		this.location2 = loc2;
//	}
//
//	function _tostring() {
//		return "BuildTruckRoad";
//	}
//
//	function Run() {
//		local a_loc = location1;
//		local b_loc = location2;
//		local dist = AIMap.DistanceManhattan(a_loc, b_loc);
//		local s_tick = AIController.GetTick();
//		local parcount = 0;
//
//		AISign.BuildSign(a_loc, "A");
//		AISign.BuildSign(b_loc, "B");
//
//		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
//		//local pathfinder = RoadPathFinder();
//		/* defaults
//		pathfinder.cost.max_cost = 2000000000;
//		pathfinder.cost.tile = 100;
//		pathfinder.cost.turn = 100;
//		pathfinder.cost.slope = 200;
//		pathfinder.cost.no_existing_road = 40;
//		pathfinder.cost.bridge_per_tile = 150;
//		pathfinder.cost.tunnel_per_tile = 120;
//		pathfinder.cost.coast = 20;
//		pathfinder.cost.max_bridge_length = 10;
//		pathfinder.cost.max_tunnel_length = 20;
//		*/
//		local pathfinder = Road();
//		pathfinder.cost.max_bridge_length = 4;
//		pathfinder.cost.max_tunnel_length = 4;
//		pathfinder.cost.max_cost = pathfinder.cost.tile * 4 * dist;
//		//pathfinder.cost.no_existing_road = 400;
//		Debug("build path from " + a_loc + " to " + b_loc);
//		pathfinder.InitializePath([a_loc], [b_loc]);
//
//		local tries = 0;
//		local path = false;
//		while (path == false) {
//			if (++tries >= MAX_TRIES) {
//				throw TaskFailedException("pathfinder couldn't find path after " + tries + " tries");
//			}
//			//path = pathfinder.FindPath(100);
//			path = pathfinder.FindPath(dist * 3 * TICKS_PER_DAY);
//			AIController.Sleep(1);
//		}
//		if (path == null) {
//			throw TaskFailedException("pathfinder.FindPath return null, no path found");
//		}
//		while (path != null) {
//		  local par = path.GetParent();
//		  if (par != null) {
//			parcount++;
//			local last_node = path.GetTile();
//			if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
//			  if (!AIRoad.BuildRoad(path.GetTile(), par.GetTile())) {
//				/* An error occured while building a piece of road. TODO: handle it.
//				 * Note that is can also be the case that the road was already build. */
//			  }
//			} else {
//			  /* Build a bridge or tunnel. */
//			  if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {
//				/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
//				if (AIRoad.IsRoadTile(path.GetTile())) AITile.DemolishTile(path.GetTile());
//				if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
//				  if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
//					/* An error occured while building a tunnel. TODO: handle it. */
//				  }
//				} else {
//				  local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
//				  bridge_list.Valuate(AIBridge.GetMaxSpeed);
//				  bridge_list.Sort(AIList.SORT_BY_VALUE, false);
//				  if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
//					/* An error occured while building a bridge. TODO: handle it. */
//				  }
//				}
//			  }
//			}
//		  }
//		  path = par;
//		}
//		local e_tick = AIController.GetTick();
//		if (parcount > 0) {
//			Debug("pathfinder took " + (e_tick - s_tick) + " secs to complete");
//			return true;
//		} else {
//			Debug("pathfinder didn't complete");
//			return false;
//		}
//	}
//
//}

class BuildTruckStation extends Task {
	location = null;
	ttype = null; // transport type
	station = null;

	// AIRoad.ROADVEHTYPE_TRUCK or AIRoad.ROADVEHTYPE_BUS
	constructor(parentTask, location, ttype = AIRoad.ROADVEHTYPE_TRUCK) {
		Task.constructor(parentTask, null);
		this.location = location;
		this.ttype = ttype;
	}
	
	function _tostring() {
		return "BuildTruckStation";
	}

	function Run() {

		local tiles = AITileList();
		SafeAddRectangle(tiles, location, 1);
		tiles.RemoveValue(location);
		tiles.Valuate(AITile.GetSlope);
		tiles.KeepValue(AITile.SLOPE_FLAT);
		tiles.Valuate(AITile.IsBuildable)
		tiles.KeepValue(1);

		//local stationtype = AIStation.STATION_NEW;
		local stationtype = AIStation.STATION_JOIN_ADJACENT;
		local tile, front;
		foreach (tile,_ in tiles) {
			if (!AITile.IsBuildableRectangle(tile, 1, 1)) { continue }
			local area = AITileList();
			SafeAddRectangle(area, tile, 1);
			area.RemoveValue(tile);
			area.Valuate(AITile.GetSlope);
			area.KeepValue(AITile.SLOPE_FLAT);
			area.Valuate(AITile.IsBuildable)
			area.KeepValue(1);
			foreach (front,_ in area) {
				if (AIRoad.BuildRoadStation(tile, front, this.ttype, stationtype)) {
					this.station = tile;
					return;
				}
			}
		}
	}

}

class BuildTruckDepot extends Task {

	location = null;
	depot = null;
	RADIUS = 15;

	constructor(parentTask, location) {
		Task.constructor(parentTask, null);
		this.location = location;
		Debug("location=", location);
	}
	
	function _tostring() {
		return "BuildTruckDepot";
	}

	function Run() {

		local centertile = this.location;
		local tiles = AITileList();
		SafeAddRectangle(tiles, centertile, this.RADIUS);
		//tiles.RemoveValue(centertile);

		// find all the roads
		local roadtiles = tiles;
		roadtiles.Valuate(AIRoad.IsRoadTile);
		roadtiles.KeepValue(1);
		if (roadtiles.Count() > 0) {
			tiles = roadtiles;
		}

		tiles.Valuate(AITile.GetDistanceManhattanToTile, centertile);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		Debug("tiles.Count()=",tiles.Count());

		/* find all flat, buildable spots along the road */
		local t, sur, s;
		foreach (t,_ in tiles) {
			sur = AITileList();
			SafeAddRectangle(sur, t, 1);
			sur.Valuate(AITile.GetSlope);
			sur.KeepValue(AITile.SLOPE_FLAT);

			sur.Valuate(AITile.IsBuildable);
			sur.KeepValue(1);

			foreach (s,_ in sur) {
				if (AIRoad.BuildRoadDepot(s, t)) {
					AIRoad.BuildRoad(s, t);
					this.depot = s;
					return;
				}
			}
		}
	}

}

class BuildTruck extends Task {

	producer = null;
	consumer = null;
	depot = null;
	cargo = null;

	constructor(parentTask, d, p, c, cargoID) {
		Task.constructor(parentTask, null);
		depot = d;
		producer = p;
		consumer = c;
		cargo = cargoID;
	}
	
	function _tostring() {
		return "BuildTruck";
	}

	function Run() {
		local z = 0;
		local ctl = AICargo.GetCargoLabel(cargo);
		AILog.Info("Pick truck for " + ctl);

		local vlist = AIEngineList(AIVehicle.VT_ROAD);
		vlist.Valuate(AIEngine.GetCargoType);
		vlist.KeepValue(cargo);
		vlist.Valuate(AIEngine.IsBuildable);
		vlist.KeepValue(1);
		vlist.Valuate(AIEngine.GetRoadType);
		vlist.KeepValue(AIRoad.ROADTYPE_ROAD);
		vlist.Valuate(AIEngine.GetCapacity);
		vlist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

		if (vlist.Count() < 1) {
			throw TaskFailedException("no engines available for cargo ", ctl);
		}

		local eID = vlist.Begin();
		Debug("Chose " + AIEngine.GetName(eID));

		local veh = AIVehicle.BuildVehicle(depot, eID);
		Debug("Is vehicle valid? ", AIVehicle.IsValidVehicle(veh));
		if (!AIVehicle.IsValidVehicle(veh)) {
			Debug("For some reason (probably not enough money), I couldn't buy a vehicle");
			throw TaskRetryException();
		}

		local flags = AIOrder.OF_NONE;
		AIOrder.AppendOrder(veh, producer, flags);
		AIOrder.AppendOrder(veh, consumer, flags);
		AIOrder.AppendOrder(veh, depot, flags);
		AIVehicle.StartStopVehicle(veh);
	}
}
