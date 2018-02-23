
class Route {
	
	routename = null;
	infos = [];
	cargo = null;
	vgroup = null;
	cost = 0;
	profit = 0;
	nethistory = [];
	waiting = [];
	full = false;

	/*
		infos = [
		{
			id = 0, // townID or industryID
			cargo = 0,
			loc = 0, // location of town or industry
			type = "town" or "industry",
			depot = location,
			stationloc = 0, // location of station
			stationID = 0,
		},
		...
		];
	*/

	function constructor(routename, cargo, full=false) {
		this.routename = routename;
		this.cargo = cargo;
		this.full = full;
		Debug("New Route called ", routename, " for cargo ", cargo);
	}

	/*
	function _rawget(key) {
		if (key == "vgroup") {
			return this.vgroup;
		}
		return null;
	}
	*/

	function Timer() {
		if (waiting.len()) {
			local vehID = waiting.pop();
			AIVehicle.StartStopVehicle(vehID);
			Debug("Activating...");
		}
	}

	function HandleEvent(e) {
		local ec, vID;
		switch (e.GetEventType()) {
			case AIEvent.ET_VEHICLE_CRASHED:
				AILog.Info("Event: vehicle crashed");
				ec = AIEventVehicleCrashed.Convert(e);
				vID  = ec.GetVehicleID();
				break;

			case AIEvent.ET_VEHICLE_LOST:
				AILog.Info("Event: vehicle lost");
				// TODO perhaps a road we don't own disappeared
				// try to rebuild the path?
				break;

			case AIEvent.ET_VEHICLE_WAITING_IN_DEPOT:
				AILog.Info("Event: vehicle waiting in depot");
				ec = AIEventVehicleWaitingInDepot.Convert(e);
				vID = ec.GetVehicleID();
				if (OurVehicle(vID)) {
					ReduceVehicleInRoute(vID);
				}
				break;

			case AIEvent.ET_VEHICLE_UNPROFITABLE:
				AILog.Info("Event: vehicle unprofitable");
				ec = AIEventVehicleUnprofitable.Convert(e);
				vID = ec.GetVehicleID();
				if (OurVehicle(vID)) {
					ReduceVehicleInRoute(vID);
				}
				break;
		}
	}

	function OurVehicle(vID) {
		local list = AIVehicleList_Group(this.vgroup);
		foreach (i,ID in list) {
			if (ID == vID) { return true }
		}
		return false;
	}

	function PrintStop(info) {
		local i;
		local keys = [
			"id",
			"cargo",
			"loc",
			"type",
			"depot",
			"stationloc",
			"stationID",
		];
		Debug("print stop info:");
		foreach (j,k in keys) {
			if (k in info) {
				Debug(k, " = " info[k]);
			} else {
				Debug(k, " is undefined");
			}
		}
	}

	// requires at least two stops, point a to b
	function AddStops(stype, ID1, ID2) {

		local i, ID;
		local arr = [ID1, ID2];

		foreach (i,ID in arr) {
			local stopinfo = GetResInfo(stype, ID);
			Debug("Stop #", i);
			PrintStop(stopinfo);
			this.infos.append(stopinfo);
		}

		if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {
			CreateBusRoute();
		} else if (AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			CreateCargoRoute();
		} else {
			CreateCargoRoute();
		}
	}

	function GetStops() {
		local i, val, info;
		local tlist = AITileList();
		local arr = [];

		Debug("before:");
		foreach (i,info in this.infos) {
			val = info.stationloc;
			arr.append(val);
			Debug("val=",val);
		}
		return arr;
	}

	function CreateBusRoute()
	{
		Debug("in CreateBusRoute()");
		local srcinfo = this.infos[0];
		local dstinfo = this.infos[1];
		AILog.Info("build road from " + srcinfo.name + " to " + dstinfo.name);
		local ret = BuildRoad(srcinfo.stationloc, dstinfo.stationloc);
		local eID = AllocateTruck(this.cargo);
		local depot = FindCloseDepot(srcinfo);
		if (depot == null) {
			AILog.Info("try to build depot in " + srcinfo.name);
			depot = NewRoadDepot(srcinfo.loc);
		} else {
			AILog.Info("use existing depot");
		}
		AILog.Info("depot is " + depot);
		AILog.Info("creating route called " + routename);

		CreateRoute(depot);
		return true;
	}

	function ExpandStation() {
		local ret = false;

		local stationloc = this.infos[0].stationloc;
		local stationfront = AIRoad.GetRoadStationFrontTile(stationloc);
		local stationID = AIStation.GetStationID(stationloc);
		local roadtype = AIRoad.ROADVEHTYPE_TRUCK;

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

		local t, front;
		local i = 1;
		local succ = false;
		for (t = tiles.Begin(); !tiles.IsEnd(); t = tiles.Next()) {
			local x = AIMap.GetTileX(t) + 1;
			local y = AIMap.GetTileY(t);
			front =  AIMap.GetTileIndex(x, y);
			ret = AIRoad.BuildRoadStation(t, front, roadtype, stationID);
			Debug("t=", t, " front=", front, " roadtype=", roadtype);	
			PrintError(ret);
			if (ret) {
				succ = true;
				break;
			}
			//AISign.BuildSign(t, ""+i);
			//i++;
		}
		if (succ == true) {
			ret = BuildRoad(stationfront, front);
			ret = BuildRoad(t, front);
		}
		return ret;

		/*
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
		*/
	}

	function AddVehicle() {
		local srcinfo = this.infos[0];
		local depot = srcinfo.depot;
		if (depot == null) {
			Debug("PROBLEM: no depot found???");
			return false;
		}
		/* or out of money? */
		Debug("depot is " + depot);

		local eID = AllocateTruck(this.cargo);
		local veh = AIVehicle.BuildVehicle(depot, eID);
		Debug("Is vehicle valid? ", AIVehicle.IsValidVehicle(veh));
		if (!AIVehicle.IsValidVehicle(veh)) {
			Debug("For some reason (probably not enough money), I couldn't buy a vehicle");
			return false;
		}

		local list = AIVehicleList_Group(this.vgroup);
		local main_veh = list.Begin();
		AIGroup.MoveVehicle(this.vgroup, veh);
		AIOrder.ShareOrders(veh, main_veh);
		this.waiting.append(veh);

		return true;
		
	}

	function VehicleCount() {
		if (this.vgroup == null) {
			return 0;
		}
		local list = AIVehicleList_Group(this.vgroup);
		return list.Count();
	}

	function _tostring() {
		return "Route";
	}

	function GetResInfo(type, ID)
	{
		local vID = AllocateTruck(this.cargo);
		local t = {
			id = ID,
			type = type,
			depot = null,
		};
		if (type == "town") {
			t.loc <- AITown.GetLocation(ID);
			t.name <- AITown.GetName(ID);
			t.stationID <- BuildStopInTown(vID, ID);
			t.stationloc <- AIStation.GetLocation(t.stationID);
		} else {
			t.loc <- AIIndustry.GetLocation(ID);
			t.name <- AIIndustry.GetName(ID);
			t.stationloc <- FindIndustryStation(t);
			t.stationID <- AIStation.GetStationID(t.stationloc);
		}
		return t;
	}

	function FindIndustryStation(info)
	{
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

	function BuildRoad(a_loc, b_loc)
	{
		local s_tick = AIController.GetTick();
		local parcount = 0;
		local pathfinder = RoadPathFinder();
		/* defaults
		pathfinder.cost.max_cost = 2000000000;
		pathfinder.cost.tile = 100;
		pathfinder.cost.no_existing_road = 40;
		pathfinder.cost.turn = 100;
		pathfinder.cost.slope = 200;
		pathfinder.cost.bridge_per_tile = 150;
		pathfinder.cost.tunnel_per_tile = 120;
		pathfinder.cost.coast = 20;
		pathfinder.cost.max_bridge_length = 10;
		pathfinder.cost.max_tunnel_length = 20;
		*/
		//AISign.BuildSign(a_loc, "FROM");
		//AISign.BuildSign(b_loc, "TO");
		Debug("build path from " + a_loc + " to " + b_loc);
		pathfinder.InitializePath([a_loc], [b_loc]);

		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

		local path = false;
		while (path == false) {
			path = pathfinder.FindPath(100);
			AIController.Sleep(1);
		}
		if (path == null) {
			AILog.Error("pathfinder.FindPath return null, no path found");
			return false;
		} else {
			while (path != null) {
			  local par = path.GetParent();
			  if (par != null) {
				parcount++;
				local last_node = path.GetTile();
				if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1 ) {
				  if (!AIRoad.BuildRoad(path.GetTile(), par.GetTile())) {
					/* An error occured while building a piece of road. TODO: handle it.
					 * Note that is can also be the case that the road was already build. */
				  }
				} else {
				  /* Build a bridge or tunnel. */
				  if (!AIBridge.IsBridgeTile(path.GetTile()) && !AITunnel.IsTunnelTile(path.GetTile())) {
					/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
					if (AIRoad.IsRoadTile(path.GetTile())) AITile.DemolishTile(path.GetTile());
					if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
					  if (!AITunnel.BuildTunnel(AIVehicle.VT_ROAD, path.GetTile())) {
						/* An error occured while building a tunnel. TODO: handle it. */
					  }
					} else {
					  local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1);
					  bridge_list.Valuate(AIBridge.GetMaxSpeed);
					  bridge_list.Sort(AIList.SORT_BY_VALUE, false);
					  if (!AIBridge.BuildBridge(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
						/* An error occured while building a bridge. TODO: handle it. */
					  }
					}
				  }
				}
			  }
			  path = par;
			}
		}
		local e_tick = AIController.GetTick();
		if (parcount > 0) {
			//AILog.Info("pathfinder took " + (e_tick - s_tick) + " secs to complete");
			return true;
		} else {
			AILog.Info("pathfinder didn't complete");
			return false;
		}
	}
	
	function BuildDepot(roadtile,centertile) {
		// this is road, check it's joined to the centre of town
		local testroad = RoadPathFinder();
		local depot = 0;

		testroad.cost.no_existing_road = testroad.cost.max_cost; // only check existing roads
		local roadtilegrid = [AIMap.GetTileX(roadtile),AIMap.GetTileY(roadtile)];
		local coords = [AIMap.GetTileX(centertile),AIMap.GetTileY(centertile)];
		testroad.InitializePath([roadtile], [centertile]);

		local path = false;
		while (path == false) {
			path = testroad.FindPath(20);
			AIController.Sleep(2);
		}
		if (path == null) {
			AILog.Info("No path found");
			return null;
		}

		if (AITile.GetSlope(roadtile) == 0)
		{
			// keep trying if a vehicle is preventing building the road connection
			//AISign.BuildSign(roadtile, "T");
			//AISign.BuildSign(centertile, "S");
			local builtlink = false;
			local c = 0;
			if (AIRoad.BuildRoadDepot (AIMap.GetTileIndex(roadtilegrid[0]+1,roadtilegrid[1]),roadtile)) {
				depot = AIMap.GetTileIndex(roadtilegrid[0]+1,roadtilegrid[1]);
				while (!builtlink && c < 100) {
					builtlink = AIRoad.BuildRoad (roadtile,depot);
					c++;
					AIController.Sleep(5);
				}
			} else if (AIRoad.BuildRoadDepot (AIMap.GetTileIndex(roadtilegrid[0]-1,roadtilegrid[1]),roadtile)) {
				depot = AIMap.GetTileIndex(roadtilegrid[0]-1,roadtilegrid[1]);
				while (!builtlink && c < 100) {
					builtlink = AIRoad.BuildRoad (roadtile,depot);
					c++;
					AIController.Sleep(5);
				}
			} else if (AIRoad.BuildRoadDepot (AIMap.GetTileIndex(roadtilegrid[0],roadtilegrid[1]+1),roadtile)) {
				depot = AIMap.GetTileIndex(roadtilegrid[0],roadtilegrid[1]+1);
				while (!builtlink && c < 100) {
					builtlink = AIRoad.BuildRoad (roadtile,depot);
					c++;
					AIController.Sleep(5);
				}
			} else if (AIRoad.BuildRoadDepot (AIMap.GetTileIndex(roadtilegrid[0],roadtilegrid[1]-1),roadtile)) {
				depot = AIMap.GetTileIndex(roadtilegrid[0],roadtilegrid[1]-1);
				while (!builtlink && c < 100) {
					builtlink = AIRoad.BuildRoad (roadtile,depot);
					c++;
					AIController.Sleep(5);
				}
			}
		}
		return depot;
	}

	function NewRoadDepot(centertile) {

		local printvals = function(arr, msg) {
			//Debug(msg, ":", arr.Count());
		}

		local tiles = AITileList();
		SafeAddRectangle(tiles, centertile, 30);
		printvals(tiles, "SafeAddRectangle");

		/* find all the roads */
		//tiles.Valuate(AITile.HasTransportType, AITile.TRANSPORT_ROAD);
		tiles.Valuate(AIRoad.IsRoadTile);
		tiles.KeepValue(1);
		printvals(tiles, "AIRoad.IsRoadTile");

		tiles.Valuate(AITile.GetDistanceManhattanToTile, centertile);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		/* find all flat, buildable spots along the road */
		local t, sur, s;
		foreach (t,z in tiles) {
			sur = AITileList();
			SafeAddRectangle(sur, t, 1);
			sur.Valuate(AITile.GetSlope);
			sur.KeepValue(AITile.SLOPE_FLAT);

			sur.Valuate(AITile.IsBuildable);
			sur.KeepValue(1);

			foreach (s,z in sur) {
				if (s == centertile) { continue }
				if (AIRoad.BuildRoadDepot(s, t)) {
					AIRoad.BuildRoad(s, t);
					return s;
				}
			}
		}
		return null;
	}

	// for industries only
	function GetBetweenTown(loc_a, loc_b)
	{
		local stat_a = AIStation.GetStationID(loc_a);
		local stat_b = AIStation.GetStationID(loc_b);
		local town1 = AIStation.GetNearestTown(stat_a);
		local town2 = AIStation.GetNearestTown(stat_b);
		if (town1 == town2) {
			return town1;
		}
		return null;
	}

	function CreateCargoRoute()
	{
		local srcinfo = this.infos[0];
		local dstinfo = this.infos[1];
		local srcloc = srcinfo.stationloc;
		local dstloc = dstinfo.stationloc;
		local eID = AllocateTruck(this.cargo);
		AILog.Info("build a stop in " + srcinfo.name);
		local stat_a = BuildCargoStop(eID,srcloc);
		this.infos[0].stationID = AIStation.GetStationID(srcloc);
		AILog.Info("build another stop in " + dstinfo.name);
		local stat_b = BuildCargoStop(eID,dstloc);
		this.infos[1].stationID = AIStation.GetStationID(dstloc);

		local ret1;
		local townID = GetBetweenTown(srcloc, dstloc);
		if (townID != null) {
			local tname = AITown.GetName(townID);
			local tloc = AITown.GetLocation(townID);
			Debug("connect ", srcinfo.name, " to ", dstinfo.name, " via ", tname);
			ret1 = BuildRoad(srcloc+1, tloc);
			ret1 = BuildRoad(dstloc+1, tloc);
			
		} else {
			// need exception handler here
			AILog.Info("build DIRECT road from " + srcinfo.name + " to " + dstinfo.name);
			ret1 = BuildRoad(srcloc+1, dstloc+1);
		}
		local ret2 = BuildRoad(srcloc, srcloc+1);
		local ret3 = BuildRoad(dstloc, dstloc+1);
		if (ret1 && ret2 && ret3) {
			AILog.Info("try to build depot in " + srcinfo.name);
			local depot = NewRoadDepot(srcloc);
			Debug("depot is " + depot);
			if (depot == null) {
				Debug("building depot failed");
				return;
			}

			this.infos[0].depot = depot;
			AILog.Info("creating route called " + routename);
			CreateRoute(depot);
		} else {
			Debug("ret1=", ret1);
			Debug("ret2=", ret2);
			Debug("ret3=", ret3);
			Debug("building roads failed, won't create route");
		}
	}

	// AIRoad.ROADVEHTYPE_BUS
	// AIRoad.ROADVEHTYPE_TRUCK
	function BuildCargoStop(vehicle,loc) {

		local cargoID = AIEngine.GetCargoType(vehicle);
		local ctn = AICargo.GetCargoLabel(cargoID);
		local stype = AIRoad.GetRoadVehicleTypeForCargo(cargoID);
		//local stationtype = AIStation.STATION_NEW;
		local stationtype = AIStation.STATION_JOIN_ADJACENT;
		local ret = AIRoad.BuildRoadStation(loc, loc+1, stype, stationtype); 
		Debug("build stop at ", loc);
		if (ret == false) { PrintError() }
		Debug("ret=", ret);
		return ret;
	}

	function BuildStopInTown(vehicle, townID) {

		local stat = AIStation.STATION_NEW;
		local cargoID = AIEngine.GetCargoType(vehicle);
		local ctn = AICargo.GetCargoLabel(cargoID);
		local stype = AIRoad.GetRoadVehicleTypeForCargo(cargoID);
		local stoptype = "UNKNOWN";
		if (stype == AIRoad.ROADVEHTYPE_BUS) {
			stoptype = "bus";
		} else if (stype == AIRoad.ROADVEHTYPE_TRUCK) {
			stoptype = "truck";
		}
		AILog.Info("build " + stoptype + " stop for " + ctn + " cargo (" +
			cargoID + ") in " + AITown.GetName(townID));

		local printvals = function(arr, msg) {
			Debug(msg, ":", arr.Count());
		}

		local valfunc = function(tile, townID) {
			return AITown.IsWithinTownInfluence(townID, tile);
		}
		local tiles = AITileList();
		SafeAddRectangle(tiles, AITown.GetLocation(townID), 30);
		tiles.Valuate(valfunc, townID);
		tiles.KeepValue(1);
		printvals(tiles, "valfun/AITown.IsWithinTownInfluence");

		//tiles.Valuate(AITile.HasTransportType, AITile.TRANSPORT_ROAD);
		tiles.Valuate(AIRoad.IsRoadTile);
		tiles.KeepValue(1);
		printvals(tiles, "AIRoad.IsRoadTile");

		tiles.Valuate(AITile.GetCargoAcceptance, cargoID, 1, 1, 1);
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
					return AIStation.GetStationID(t);
				}
			}
		}
		return null;
	}

	function BuildStop(vehicle,xoff,yoff,count,spread,centertile,rem,spike) {

		// clockwise spiral out
		local trytilegrid = [
			((AIMap.GetTileX(centertile))+xoff),
			((AIMap.GetTileY(centertile))+yoff)
		];
		//AISign.BuildSign(centertile, "start");
		local x = 0;
		local y = 0;
		local i = 0;
		spike = false;
		local cargoID = AIEngine.GetCargoType(vehicle);
		local ctn = AICargo.GetCargoLabel(cargoID);
		local stype = AIRoad.GetRoadVehicleTypeForCargo(cargoID);
		local stoptype = "UNKNOWN";
		if (stype == AIRoad.ROADVEHTYPE_BUS) {
			stoptype = "bus";
		} else if (stype == AIRoad.ROADVEHTYPE_TRUCK) {
			stoptype = "truck";
		}
		AILog.Info("build " + stoptype + " stop for " + ctn + " cargo (" +
			cargoID + ") at " + trytilegrid[0] + "," + trytilegrid[1]);

		local trystation = function (stype, cargotype, trytilegrid, centertile, x, y)
		{
			local trytile = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y);
			local aimx  = AIMap.GetTileIndex(trytilegrid[0]+x+1,trytilegrid[1]+y);
			local aimy  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y+1);
			local aimxm  = AIMap.GetTileIndex(trytilegrid[0]+x-1,trytilegrid[1]+y);
			local aimym  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y-1);
			local stat = AIStation.STATION_NEW;
			//AILog.Info("trytile=" + trytile);
			//AISign.BuildSign(trytile, "?");

			local testroad = RoadPathFinder();
			testroad.cost.no_existing_road = testroad.cost.max_cost;
			testroad.InitializePath([trytile], [centertile]);
			local path = false;
			while (path == false) {
				path = testroad.FindPath(20);
				AIController.Sleep(1);
			}
			if (path == null) return null;

			//&& (AIRoad.HasRoadType(trytile,AIRoad.ROADTYPE_ROAD)))
			//AISign.BuildSign(trytile, "X");
			local cp = AITile.GetCargoProduction(trytile, cargotype, 1, 1, 5);
			local ca = AITile.GetCargoAcceptance(trytile, cargotype, 1, 1, 5);
			if (cp > 11 || ca > 11)
			{
				//AILog.Info("cargo accepted here");
				//AISign.BuildSign(trytile, "X");
				if (!AIBridge.IsBridgeTile(aimx)
					&& !AIBridge.IsBridgeTile(aimxm)
					&& (AITile.GetSlope(aimx) == AITile.SLOPE_FLAT)
					&& (AITile.GetSlope(aimxm) == AITile.SLOPE_FLAT)
					&& AIRoad.BuildDriveThroughRoadStation(trytile,aimx,stype,stat))
				{
					//AILog.Info("success at " + trytile);
					return AIStation.GetStationID(trytile);
				} else if (!AIBridge.IsBridgeTile(aimy)
					&& !AIBridge.IsBridgeTile(aimym)
					&& (AITile.GetSlope(aimy) == AITile.SLOPE_FLAT)
					&& (AITile.GetSlope(aimym) == AITile.SLOPE_FLAT)
					&& AIRoad.BuildDriveThroughRoadStation(trytile,aimy,stype,stat))
				{
					//AILog.Info("OR success at " + trytile);
					return AIStation.GetStationID(trytile);
				}
				//AILog.Info("but couldn't find a spot");
			}
			//AILog.Info("cargo not accepted here");
			return null;
		}

		local stationID = null;
		spread = 10;
		while ((i < spread))
		{
			for (;y >= 0-i;y--) {
				stationID = trystation(stype, cargoID, trytilegrid, centertile, x, y);
				if (stationID) { return stationID; }
			}

			for (;x >= 0-i;x--) {
				stationID = trystation(stype, cargoID, trytilegrid, centertile, x, y);
				if (stationID) { return stationID; }
			}

			for (;y <= i;y++) {
				stationID = trystation(stype, cargoID, trytilegrid, centertile, x, y);
				if (stationID) { return stationID; }
			}

			for (;x <= i+1;x++) {
				stationID = trystation(stype, cargoID, trytilegrid, centertile, x, y);
				if (stationID) { return stationID; }
			}
			i=i+1
		}
		AILog.Info("Failed to build stop");
		return false;
	}

	function BuildBusStop(xoff,yoff,count,spread,town,rem,spike) {

		// clockwise spiral out
		local trytilegrid = [((AIMap.GetTileX(AITown.GetLocation(town)))+xoff),((AIMap.GetTileY(AITown.GetLocation(town)))+yoff)]
		local trytile;
		local aimx; // aimtile
		local aimy; // aimtile
		local aimxm; // an additional aimtile, for bridge approach tests (we don't build on bridge approaches, because they send us on journeys)
		local aimym; // an additional aimtile, for bridge approach tests (we don't build on bridge approaches, because they send us on journeys)
		local testroad = RoadPathFinder();
		testroad.cost.no_existing_road = testroad.cost.max_cost;
		local x = 0
		local y = 0
		local i = 0
		local stat = AIStation.STATION_NEW

		local statcount = 0

		while ((i < spread) && (statcount < count)) {
		//y--
		for (;y >= 0-i;y--) {
		trytile = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y);
		aimx  = AIMap.GetTileIndex(trytilegrid[0]+x+1,trytilegrid[1]+y);
		aimy  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y+1);
		aimxm  = AIMap.GetTileIndex(trytilegrid[0]+x-1,trytilegrid[1]+y);
		aimym  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y-1);

		testroad.InitializePath([trytile], [AITown.GetLocation(town)]);
		local path = false;
		while (path == false) {
		path = testroad.FindPath(20);
		AIController.Sleep(1);
		}

		//AISign.BuildSign(trytile, "X");
		if (rem) {
		AIRoad.RemoveRoadStation(trytile) } else
		if ((path != null) && (statcount < count) && (AITile.GetCargoAcceptance(trytile, 0, 1, 1, 3) > 11) && (AIRoad.HasRoadType(trytile,AIRoad.ROADTYPE_ROAD))) {
			if (!AIBridge.IsBridgeTile(aimx) && !AIBridge.IsBridgeTile(aimxm) &&
			(AITile.GetSlope(aimx) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimxm) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimx,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeX(trytile,town);
				}
				}
			else if (!AIBridge.IsBridgeTile(aimy) && !AIBridge.IsBridgeTile(aimym) &&
			(AITile.GetSlope(aimy) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimym) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimy,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeY(trytile,town);
				}
				}
		}
		}

		//x--;
		for (;x >= 0-i;x--) {
		trytile = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y);
		aimx  = AIMap.GetTileIndex(trytilegrid[0]+x+1,trytilegrid[1]+y);
		aimy  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y+1);
		aimxm  = AIMap.GetTileIndex(trytilegrid[0]+x-1,trytilegrid[1]+y);
		aimym  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y-1);

		testroad.InitializePath([trytile], [AITown.GetLocation(town)]);
		local path = false;
		while (path == false) {
		path = testroad.FindPath(20);
		AIController.Sleep(1);
		}
		//AISign.BuildSign(trytile, "x");
		if (rem) {
		AIRoad.RemoveRoadStation(trytile) } else
		if ((path != null) && (statcount < count) && (AITile.GetCargoAcceptance(trytile, 0, 1, 1, 3) > 11) && (AIRoad.HasRoadType(trytile,AIRoad.ROADTYPE_ROAD))) {
			if (!AIBridge.IsBridgeTile(aimx) && !AIBridge.IsBridgeTile(aimxm) &&
			(AITile.GetSlope(aimx) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimxm) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimx,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeX(trytile,town);
				}
				}
			else if (!AIBridge.IsBridgeTile(aimy) && !AIBridge.IsBridgeTile(aimym) &&
			(AITile.GetSlope(aimy) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimym) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimy,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeY(trytile,town);
				}
				}
		}
		}

		//AISign.BuildSign(trytile, "x");
		//y++;
		for (;y <= i;y++) {
		trytile = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y);
		aimx  = AIMap.GetTileIndex(trytilegrid[0]+x+1,trytilegrid[1]+y);
		aimy  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y+1);
		aimxm  = AIMap.GetTileIndex(trytilegrid[0]+x-1,trytilegrid[1]+y);
		aimym  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y-1);

		testroad.InitializePath([trytile], [AITown.GetLocation(town)]);
		local path = false;
		while (path == false) {
		path = testroad.FindPath(20);
		AIController.Sleep(1);
		}
		//AISign.BuildSign(trytile, "y");
		if (rem) {
		AIRoad.RemoveRoadStation(trytile) } else
		if ((path != null) && (statcount < count) && (AITile.GetCargoAcceptance(trytile, 0, 1, 1, 3) > 11) && (AIRoad.HasRoadType(trytile,AIRoad.ROADTYPE_ROAD))) {
			if (!AIBridge.IsBridgeTile(aimx) && !AIBridge.IsBridgeTile(aimxm) &&
			(AITile.GetSlope(aimx) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimxm) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimx,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeX(trytile,town);
				}
				}
			else if (!AIBridge.IsBridgeTile(aimy) && !AIBridge.IsBridgeTile(aimym) &&
			(AITile.GetSlope(aimy) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimym) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimy,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeY(trytile,town);
				}
				}
		}
		}

		//x++;
		for (;x <= i+1;x++) {
		trytile = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y);
		aimx  = AIMap.GetTileIndex(trytilegrid[0]+x+1,trytilegrid[1]+y);
		aimy  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y+1);
		aimxm  = AIMap.GetTileIndex(trytilegrid[0]+x-1,trytilegrid[1]+y);
		aimym  = AIMap.GetTileIndex(trytilegrid[0]+x,trytilegrid[1]+y-1);

		testroad.InitializePath([trytile], [AITown.GetLocation(town)]);
		local path = false;
		while (path == false) {
		path = testroad.FindPath(20);
		AIController.Sleep(1);
		}
		//AISign.BuildSign(trytile, "x");
		if (rem) {
		AIRoad.RemoveRoadStation(trytile) } else
		if ((path != null) && (statcount < count) && (AITile.GetCargoAcceptance(trytile, 0, 1, 1, 3) > 11) && (AIRoad.HasRoadType(trytile,AIRoad.ROADTYPE_ROAD))) {
			if (!AIBridge.IsBridgeTile(aimx) && !AIBridge.IsBridgeTile(aimxm) &&
			(AITile.GetSlope(aimx) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimxm) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimx,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeX(trytile,town);
				}
				}
			else if (!AIBridge.IsBridgeTile(aimy) && !AIBridge.IsBridgeTile(aimym) &&
			(AITile.GetSlope(aimy) == AITile.SLOPE_FLAT) &&
			(AITile.GetSlope(aimym) == AITile.SLOPE_FLAT) &&
			AIRoad.BuildDriveThroughRoadStation(trytile,aimy,AIRoad.ROADVEHTYPE_BUS,stat)) {
			stat = AIStation.GetStationID(trytile), statcount = statcount+1
				if (spike) {
				SpikeY(trytile,town);
				}
				}
		}
		}
		i=i+1
		}
		if (statcount > 0) { return stat+1 } else { return false }
	}

	function CreateRoute(depot) {

		local obus;
		local clonebus;
		local stop;
		local nx;
		local name;
		local changename = false;
		local ret;
		local vehicles = [];
		local count = 4;
		Debug("in CreateRoute()");

		this.vgroup = AIGroup.CreateGroup(AIVehicle.VT_ROAD);
		local srcinfo = this.infos[0];
		local dstinfo = this.infos[1];

		AIGroup.SetName(this.vgroup, this.routename);

		local stops = GetStops();

		AILog.Info("building vehicles");
		local vehicle = AllocateTruck(this.cargo);
		obus = AIVehicle.BuildVehicle(depot,vehicle);
		Debug("Is vehicle valid? ", AIVehicle.IsValidVehicle(obus));
		if (!AIVehicle.IsValidVehicle(obus)) {
			Debug("For some reason (probably not enough money), I couldn't buy a bus for " + routename + ".")
			return false;
		}

		local AddOrder = function (obus, stop, options) {
			local sID = AIStation.GetStationID(stop);
			Debug("sID=", sID);
			Debug("is station ", stop, " valid? ", AIStation.IsValidStation(sID));
			Debug("are order flags valid? ", AIOrder.AreOrderFlagsValid(stop, options));
			local ret = AIOrder.AppendOrder(obus, stop, options);
			if (ret == false) { PrintError() }
		}
		local options = AIOrder.OF_NON_STOP_INTERMEDIATE;
		local srcflags = options;
		if (this.full) {
			srcflags += AIOrder.OF_FULL_LOAD_ANY;
		}
		AddOrder(obus, stops[0], srcflags);

		local dstflags = options + AIOrder.OF_UNLOAD + AIOrder.OF_NO_LOAD;
		if (AICargo.HasCargoClass(this.cargo, AICargo.CC_PASSENGERS) ||
			AICargo.HasCargoClass(this.cargo, AICargo.CC_MAIL))
		{
			dstflags = srcflags;
		}
		AddOrder(obus, stops[1], dstflags);

		local distance = AIMap.DistanceManhattan(stops[0], stops[1]);
		local num = distance / 15; // one truck per 15 tiles
		count = num.tointeger();

		local depotflags = options + AIOrder.OF_SERVICE_IF_NEEDED;
		AddOrder(obus, depot, depotflags);
		AILog.Info("I've bought a bus for " + routename + ".");
		AIGroup.MoveVehicle(vgroup, obus);
		//AIVehicle.StartStopVehicle(obus);
		vehicles.append(obus);

		for (local c = 1; c < count; c++) {

			Debug("cloning vehicle");
			clonebus = AIVehicle.BuildVehicle(depot,vehicle)
			if (AIVehicle.IsValidVehicle(clonebus)) {
				AIOrder.ShareOrders(clonebus,obus);

				nx = 0
				name = null
				changename = false
				while (!changename && (nx < 1000)) {
					nx++
					name = (routename + " " + nx)
					changename = AIVehicle.SetName(clonebus,name)
				}
				AIOrder.SkipToOrder(clonebus,AIBase.RandRange(AIOrder.GetOrderCount(clonebus)));
				AILog.Info("I've bought another bus for " + routename + ".")
				AIGroup.MoveVehicle(vgroup, clonebus);
				//AIVehicle.StartStopVehicle(clonebus);
				vehicles.append(clonebus);
			} else {
				AILog.Info("For some reason (probably not enough money), I couldn't buy a bus for " + routename + ".")
			}
		}
		this.waiting = vehicles;
		return true;
	}

	// cargotype = AICargo.CC_PASSENGERS
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

	function ReduceVehicleInRoute(vID)
	{
		if (AIVehicle.IsStoppedInDepot(vID)) {
			Debug("Selling vehicle ", vID);
			AIVehicle.SellVehicle(vID);
		} else {
			Debug("Sending vehicle to depot for destruction");
			AIVehicle.SendVehicleToDepot(vID);
		}
	}

	function FindCloseDepot(srcinfo) {
		local ttype = AITile.TRANSPORT_ROAD;
		local dlist = AIDepotList(ttype);
		dlist.Valuate(AITile.GetDistanceManhattanToTile, srcinfo.loc);
		dlist.KeepBelowValue(5);
		local depot = null;
		if (dlist.Count() > 0) {
			dlist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
			depot = dlist.Begin();
		}
		return depot;
	}

}
