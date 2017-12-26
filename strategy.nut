
class Strategy {

	desc = "base strategy class";
	routes = [];
	tasks = [];

	function Start() {
	}

	function Stop() {
	}

	function Uninit() {
	}

	function Save() {
		local Save = {};
		return Save;
	}

	function Load(version, data) {
	}

	// handle events
	function Event(e) {
	}

	// replace with some sort of Task list
	function Wake() {
	}

	function RunTasks() {
		local task;
		while (tasks.len() > 0) {
			try {
				// run the next task in the queue
				task = tasks[0];
				Debug("Running: " + task);
				task.Run();
				tasks.remove(0);
			} catch (e) {
				if (typeof(e) == "instance") {
					if (e instanceof TaskRetryException) {
						AIController.Sleep(e.sleep);
						Debug("Retrying...");
					} else if (e instanceof TaskFailedException) {
						Warning(task + " failed: " + e);
						tasks.remove(0);
						task.Failed();
					} else if (e instanceof NeedMoneyException) {
						Debug(task + " needs £" + e.amount);
						minMoney = e.amount;
					}
				} else {
					Error("Unexpected error");
					return;
				}
			}
		}
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

class BuildTransferCargoLine extends BuildCargoLine {
	producer_info = null;
	consumer_info = null;
	cargo = null;

	constructor(parentTask, producer_info, consumer_info, cargo) {
		Task.constructor(parentTask, null);
		/*
		producer_info = {
			id = industry or town ID,
			type = either AISubsidy.SPT_TOWN or AISubsidy.SPT_INDUSTRY
		}
		*/
		this.producer_info = producer_info;
		this.consumer_info = consumer_info;
		this.cargo = cargo;
		Debug("cargo is ", cargo);

		SetAttributes(this.producer_info);
		SetAttributes(this.consumer_info);

		PrintAttributes("producer_info", this.producer_info);
		PrintAttributes("consumer_info", this.consumer_info);
	}

	function _tostring() {
		return "BuildTransferLine";
	}

	function PrintAttributes(title, info) {
		local k,v;
		Debug(title, " table:");
		foreach (k,v in info) {
			Debug(k," ",v);
		}
	}

	function SetAttributes(info) {
		if (info.type == AISubsidy.SPT_TOWN) {
			info.name <- AITown.GetName(info.id);
			info.loc <- AITown.GetLocation(info.id);
		} else {
			info.name <- AIIndustry.GetName(info.id);
			info.loc <- AIIndustry.GetLocation(info.id);
		}
	}

	function Run() {
		
		local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
		local railType = SelectRailType(cargo);
		AIRail.SetCurrentRailType(railType);
		
		Debug("Selected:", AICargo.GetCargoLabel(cargo), "from", producer_info.name, "to", consumer_info.name);

		local a = producer_info.id;
		local b = consumer_info.id;
		
		// [siteA, rotA, dirA, siteB, rotB, dirB]
		local sites = FindStationSites(a, b);
		if (sites == null) {
			Debug("Cannot build both stations");
			throw TaskRetryException();
		}
		
		local siteA = sites[0];
		local rotA = sites[1];
		local dirA = sites[2];
		local stationA = TerminusStation(siteA, rotA, CARGO_STATION_LENGTH);
		local depotA = stationA.GetRoadDepot();
		
		local siteB = sites[3];
		local rotB = sites[4];
		local dirB = sites[5];
		local stationB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH);
		local depotB = stationB.GetRoadDepot();

		local network = Network(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
		local fromFlags = AIOrder.OF_NONE;
		local toFlags = fromFlags;

		// if transfer, build city stop, then transfer station
		// link city stop to station
		// if direct station, build
		// link stations

		subtasks = [];

		if (producer_info.type == AISubsidy.SPT_TOWN) {
			Debug(producer_info.name, " is a town");
			siteA = FindStationSite(producer_info.id, rotA, dirA);
			Debug("siteA is ", siteA);
			subtasks.append(BuildTransferCargoLine(this, producer_info,
				consumer_info, cargo));
		} else {
			subtasks.append(BuildCargoStation(this, siteA, dirA, network, a, b, cargo, true, CARGO_STATION_LENGTH));
		}

		if (consumer_info.type == AISubsidy.SPT_TOWN) {
			Debug(consumer_info.name, " is a town");
			siteB = FindStationSite(consumer_info.id, rotB, dirB);
			Debug("siteB is ", siteB);
			subtasks.append(BuildTransferCargoLine(this, consumer_info,
				producer_info, cargo));
		} else {
			subtasks.append(BuildCargoStation(this, siteB, dirB, network, b, a, cargo, false, CARGO_STATION_LENGTH));
		}

		subtasks.extend([
			// location, direction, network, atIndustry, toIndustry, cargo isSource, platformLength
			BuildTrack(this, Swap(stationA.GetEntrance()), stationB.GetEntrance(), [], SignalMode.NONE, network, BuildTrack.FAST),
			//firstTrack,
			BuildTrain2(siteA, siteB, depotA, depotB, network, fromFlags, toFlags, cargo),
			//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
			//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
			//BuildTrack(this, Swap(stationA.GetEntrance()), Swap(stationB.GetExit()), [], SignalMode.BACKWARD, network),
			//BuildSignals(this, firstTrack, SignalMode.FORWARD),
		]);
		
		RunSubtasks();
	}

	function BuildStations(info) {
		if (info.type == AISubsidy.SPT_TOWN) {
			if (FindStationSite(town, stationRotation, destination))
			subtasks.append(BuildStopInTown(this, info.id, cargo));
		} else {
		}
	}

	function FindStationSites(a, b) {
		local locA = producer_info.loc;
		local locB = consumer_info.loc;
		
		local nameA = producer_info.name;
		local dirA = StationDirection(locA, locB);
		local rotA = BuildTerminusStation.StationRotationForDirection(dirA);
		local siteA;
		if (producer_info.type == AISubsidy.SPT_TOWN) {
			siteA = FindTransferStationSite(producer_info.loc,
				rotA, consumer_info.loc);
		} else {
			siteA = FindIndustryStationSite(a, true, rotA, locB);
		}

		local nameB = consumer_info.name;
		local dirB = StationDirection(locB, locA);
		local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
		local siteB;
		if (consumer_info.type == AISubsidy.SPT_TOWN) {
			siteB = FindTransferStationSite(consumer_info.loc,
				rotB, producer_info.loc);
		} else {
			siteB = FindIndustryStationSite(b, false, rotB, locA);
		}
		
		if (siteA && siteB) {
			return [siteA, rotA, dirA, siteB, rotB, dirB];
		} else {
			Debug("Cannot build a station at " + (siteA ? nameB : nameA));
			return null;
		}
	}

	function FindTransferStationSite(location, stationRotation, destination) {
		local TRANSFER_RADIUS = 5;
		local area = AITileList();
		SafeAddRectangle(area, location, TRANSFER_RADIUS);
		
		// room for a station
		area.Valuate(IsBuildableRectangle, stationRotation, [0, -1], [1, CARGO_STATION_LENGTH + 1], true);
		area.KeepValue(1);
		
		// pick the tile farthest from the destination for increased profit
		area.Valuate(AITile.GetDistanceManhattanToTile, destination);
		area.KeepTop(1);
		
		// pick the tile closest to the industry for looks
		//area.Valuate(AITile.GetDistanceManhattanToTile, location);
		//area.KeepBottom(1);
		
		return area.IsEmpty() ? null : area.Begin();
	}
	
	/**
	 * Find a site for a station at the given industry.
	 */
	function FindIndustryStationSite(industry, producing, stationRotation, destination) {
		local location = AIIndustry.GetLocation(industry);
		local area = producing ? AITileList_IndustryProducing(industry, RAIL_STATION_RADIUS) : AITileList_IndustryAccepting(industry, RAIL_STATION_RADIUS);
		
		// room for a station
		area.Valuate(IsBuildableRectangle, stationRotation, [0, -1], [1, CARGO_STATION_LENGTH + 1], true);
		area.KeepValue(1);
		
		// pick the tile farthest from the destination for increased profit
		area.Valuate(AITile.GetDistanceManhattanToTile, destination);
		area.KeepTop(1);
		
		// pick the tile closest to the industry for looks
		//area.Valuate(AITile.GetDistanceManhattanToTile, location);
		//area.KeepBottom(1);
		
		return area.IsEmpty() ? null : area.Begin();
	}
}

class BuildStopInTown extends Task {

	townID = null;
	cargo = null;

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

		local tiles = AITileList();
		SafeAddRectangle(tiles, AITown.GetLocation(townID), 30);
		tiles.Valuate(AITile.GetTownAuthority);
		tiles.KeepValue(townID);
		printvals(tiles, "AITile.GetTownAuthority");

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
					return;
				}
			}
		}
		throw TaskFailedException("no place to build a " + stoptype + " station");
	}
}

class BuildNamedCargoLine extends BuildCargoLine {

	producer = null;
	consumer = null;
	cargo = null;

	constructor(parentTask, producer, consumer, cargo) {
		Task.constructor(parentTask, null);
		this.producer = producer;
		this.consumer = consumer;
		this.cargo = cargo;
		Debug("cargo is ", cargo);
	}

	function _tostring() {
		return "BuildNamedCargoLine";
	}

	function Run() {
		if (routes.len() == 0) {
			local r = CargoRoute(producer, consumer, cargo)
			this.routes.append(r);
		}
		
		if (!subtasks) {
			if (routes.len() == 0) {
				throw TaskFailedException("no cargo routes");
			}
			
			local route = routes[0];
			routes.remove(0);
			
			local cargo = route.cargo;
			local a = route.from;
			local b = route.to;
			
			local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
			local railType = SelectRailType(cargo);
			AIRail.SetCurrentRailType(railType);
			
			/*
			if (AIIndustry.GetAmountOfStationsAround(a) > 0) {
				Debug(AIIndustry.GetName(a), "is already being served");
				throw TaskRetryException();
			}
			*/

			Debug("Selected:", AICargo.GetCargoLabel(cargo), "from", AIIndustry.GetName(a), "to", AIIndustry.GetName(b));
			
			// [siteA, rotA, dirA, siteB, rotB, dirB]
			local sites = FindStationSites(a, b);
			if (sites == null) {
				Debug("Cannot build both stations");
				throw TaskRetryException();
			}
			
			local siteA = sites[0];
			local rotA = sites[1];
			local dirA = sites[2];
			local stationA = TerminusStation(siteA, rotA, CARGO_STATION_LENGTH);
			local depotA = stationA.GetRoadDepot();
			
			local siteB = sites[3];
			local rotB = sites[4];
			local dirB = sites[5];
			local stationB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH);
			local depotB = stationB.GetRoadDepot();
			
			// double track cargo lines discarded: we just use them for cheap starting income
			// old strategy: build the first track and two trains first, which can then finance the upgrade to double track
			//local reserved = stationA.GetReservedEntranceSpace();
			//reserved.extend(stationB.GetReservedExitSpace());
			//local exitA = Swap(TerminusStation(siteA, rotA, CARGO_STATION_LENGTH).GetEntrance());
			//local exitB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH).GetEntrance();
			//local firstTrack = BuildTrack(stationA.GetExit(), stationB.GetEntrance(), reserved, SignalMode.NONE, network);
			
			local network = Network(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
			local fromFlags = AIOrder.OF_NONE;
			local toFlags = fromFlags;
			subtasks = [
				// location, direction, network, atIndustry, toIndustry, cargo isSource, platformLength
				BuildCargoStation(this, siteA, dirA, network, a, b, cargo, true, CARGO_STATION_LENGTH),
				BuildCargoStation(this, siteB, dirB, network, b, a, cargo, false, CARGO_STATION_LENGTH),
				BuildTrack(this, Swap(stationA.GetEntrance()), stationB.GetEntrance(), [], SignalMode.NONE, network, BuildTrack.FAST),
				//firstTrack,
				BuildTrain2(siteA, siteB, depotA, depotB, network, fromFlags, toFlags, cargo),
				//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
				//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
				//BuildTrack(this, Swap(stationA.GetEntrance()), Swap(stationB.GetExit()), [], SignalMode.BACKWARD, network),
				//BuildSignals(this, firstTrack, SignalMode.FORWARD),
			];
		}
		
		RunSubtasks();

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

class BuildTrain2 extends BuildTrain {

	fromtile = null;
	totile = null;
	
	constructor(fromtile, totile, fromDepot, toDepot, network, fromFlags, toFlags, cargo = null, cheap = false) {
		this.fromtile = fromtile;
		this.totile = totile;
		BuildTrain.constructor(from, to, fromDepot, toDepot, network, fromFlags, toFlags, cargo, cheap);
	}

	function _tostring() {
		return "BuildTrain2";
	}

	function Run() {
		this.from = AIStation.GetStationID(this.fromtile);
		this.to = AIStation.GetStationID(this.totile);
		Debug("from is ", this.from, " to is ", this.to);

		this.fromDepot = ClosestDepot(this.from);
		this.toDepot = ClosestDepot(this.to);
		Debug("fromDepot is ", this.fromDepot, " toDepot is ", this.toDepot);
		BuildTrain.Run();
	}

	function ClosestDepot(station) {
		local depotList = AIList();
		foreach (depot in network.depots) {
			depotList.AddItem(depot, 0);
		}
		
		depotList.Valuate(AIMap.DistanceManhattan, AIStation.GetLocation(station));
		depotList.KeepBottom(1);
		return depotList.IsEmpty() ? null : depotList.Begin();
	}

}

class SimpleSuppliesStrategy extends Strategy {
	desc = "make supply routes which are somewhat close together";
	routes = [];
	maxdistance = 0;
	mindistance = 0;

	constructor(min=20, max=50) {
		maxdistance = max;
		mindistance = min;
	}

	function Start() {
		Wake();
	}

	function Wake() {
		local routelist = FindSupplyRoutes();
		if (routelist.len() > 0) {
			local r = routelist.pop();
			routes.append(r);
			local cargo = r[0];
			local producer = r[1];
			local consumer = r[2];
			tasks.append(BuildNamedCargoLine(null, producer, consumer, cargo));
		}
	}

	function FindSupplyRoutes() {
		local cargo;
		local routelist = []; // pID, aID, distance between them
		foreach (cargo in GenCargos()) {
			local producing = AIIndustryList_CargoProducing(cargo);
			local accepting = AIIndustryList_CargoAccepting(cargo);
			local pID, aID;
			foreach (pID,_ in producing) {
				local ploc = AIIndustry.GetLocation(pID);
				local acc2 = accepting;
				foreach (aID,_ in acc2) {
					if (pID == aID) continue;
					local aloc = AIIndustry.GetLocation(aID);
					local dist = AITile.GetDistanceManhattanToTile(ploc, aloc);
					if (RouteTaken(cargo, pID, aID, dist)) {
						continue;
					} else if (dist >= this.mindistance && dist <= this.maxdistance) {
						local arr = [ cargo, pID, aID, dist ];
						routelist.append(arr);
					}
				}
			}
		}

		local sortfunc = function(a,b) {
			if (a[3] > b[3]) return 1;
			else if (a[3] < b[3]) return -1;
			return 0;
		}

		Debug("routelist.len() is ", routelist.len());
		if (routelist.len() > 0) {
			routelist.sort(sortfunc);
			local r;
			foreach (r in routelist) {
				local pname = AIIndustry.GetName(r[1]);
				local aname = AIIndustry.GetName(r[2]);
				local dist = r[2];
				Debug("distance from ", pname, " to ", aname, " is ", dist);
			}
		}
		return routelist;
	}

	function RouteTaken(cargo, pID, aID, dist) {
		local r;
		foreach (r in this.routes) {
			if (r[0] == cargo && r[1] == pID && r[2] == aID && r[3] == dist) {
				return true;
			}
		}
		return false;
	}
}

class BasicCoalStrategy extends Strategy {

	desc = "make one route (for testing)";
	depotct = 1.0;

	function Start() {
		local cargoIDs = GenCargos();
		// connect industry tasks.push();
		// subtasks are:
		// stationA
		// stationB
		// connect the two
		// make vehicles

		tasks.append(BuildCoalLine(null, cargoIDs.OIL_));
	}

	function Wake() {
		if (tasks.len() != 0) {
			local task = tasks.pop();
			task.Run();
		}
	}

/*
	function Wake() {
		local route, stationID, info, cargoID, rating, vct, ret;
		foreach (route in this.routes) {
			route.Timer();

			cargoID = route.cargo;
			info = route.infos[0];
			stationID = info.stationID;
			vct = route.VehicleCount();
			Debug("vehicle count is " + vct);
			Debug("depotct is " + this.depotct);
			if (AIStation.HasCargoRating(stationID, cargoID)) {
				rating = AIStation.GetCargoRating(stationID, cargoID);
				Debug("rating is " + rating);
				if (rating < 65) {
					route.AddVehicle();
					Debug("expand the station");
				}
			} 
			Debug("((vct / 4.0) > this.depotct) is " + ((vct / 4.0) > this.depotct));
			if ((vct / 4.0) > this.depotct) {
				Debug("expand the station");
				ret = route.ExpandStation();
				if (ret == true) {
					this.depotct++;
				}
			}
		}
	}
*/

	function ConnectIndustry(routename, cargoID) {
		local prodlist = AIIndustryList_CargoProducing(cargoID);
		local acclist = AIIndustryList_CargoAccepting(cargoID);
		AILog.Info("prodlist count=" + prodlist.Count());
		local pID = prodlist.Begin();
		AILog.Info("acclist count=" + acclist.Count());
		local aID = acclist.Begin();

		local stype = "industry";
		local r = Route(routename, cargoID, true);
		r.AddStops(stype, pID, aID);
		this.routes.append(r);
	}

}

class LoanStrategy extends Strategy {
	companyID = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
}

class MaxLoanStrategy extends LoanStrategy {
	name = "max loan";
	desc = "grab all the loan money I can get";

	function Wake() {
		local Me = this.companyID;
		local intval = AICompany.GetLoanInterval();
		local max = AICompany.GetMaxLoanAmount();
		local balance = AICompany.GetBankBalance(Me);
		Debug("interval=" + intval + " max=" + max + " balance=" + balance);
		local loan = max;
		Debug("I want to get a loan of " + loan);
		local ret = AICompany.SetMinimumLoanAmount(loan);
		balance = AICompany.GetBankBalance(Me);
		Debug("ret=" + ret + " no my balance is " + balance);
	}
}

class ZeroLoanStrategy extends LoanStrategy {
	desc = "return all the loan money I can";

	function Wake() {
		local Me = this.companyID;
		local intval = AICompany.GetLoanInterval();
		local balance = AICompany.GetBankBalance(Me);
		local currloan = AICompany.GetLoanAmount();
		Debug("current loan is " + currloan);
		Debug("interval=" + intval + " currloan=" + currloan + " balance=" + balance);
		if (currloan < 1) {
			return;
		}
		local loan, ct;
		if (balance > currloan) {
			ct = currloan / intval;
		} else {
			ct = balance / intval;
		}
		loan = currloan - (intval * ct);
		Debug("I want set my loan to " + loan);
		local ret = AICompany.SetLoanAmount(loan);
		Debug("ret=" + ret);
	}
}

class ChooStrategy extends Strategy {
	desc = "choo's strategy";
	function Start() {
		tasks.append(BuildNewNetwork(null));
	}
}

class SubStrategy extends Strategy {

	desc = "grab all the subsidies";
	subsidies = {
		totals = {
			total = 0,
			won = 0,
			lost = 0,
			expired = 0,
			active = 0,
			inactive = 0,
		},
	};

	function Save() {
		local Save = {
			subsidies = subsidies,
		};
		return Save;
	}

	function Load(version, data) {

		//routes = data.routes;
		//RouteStats();
		subsidies = data.subsidies;
		SubsidyStats();
		//tasks = data.tasks;
		//timer = data.timer;
	}

	function Start() {
		local sublist = AISubsidyList();
		local subID = 0;
		foreach (subID,z in sublist) {
			Handle_subsidy_offer(subID);
		}
	}

	function Wake() {
	}

	function Event(e) {
		local ec;
		local sube, subID;
		local coID, vID;
		local i, route;
		local Me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
		switch (e.GetEventType()) {

			case AIEvent.ET_VEHICLE_CRASHED:
			case AIEvent.ET_VEHICLE_LOST:
			case AIEvent.ET_VEHICLE_WAITING_IN_DEPOT:
			case AIEvent.ET_VEHICLE_UNPROFITABLE:
				foreach (i,route in this.routes) {
					route.HandleEvent(e);
				}
				break;

			//case AIEvent.ET_INVALID:
			//case AIEvent.ET_TEST:

			case AIEvent.ET_SUBSIDY_OFFER:
				AILog.Info("Event: Subsidy offered");
				sube = AIEventSubsidyOffer.Convert(e);
				subID = sube.GetSubsidyID();
				Handle_subsidy_offer(subID);
				break;

			case AIEvent.ET_SUBSIDY_OFFER_EXPIRED:
				AILog.Info("Event: Subsidy offer expired");
				sube = AIEventSubsidyExpired.Convert(e);
				subID = sube.GetSubsidyID();
				if (subID in this.subsidies) {
					this.subsidies.totals.active--;
					delete this.subsidies[subID];
				}
				this.subsidies.totals.expired++;
				break;

			case AIEvent.ET_SUBSIDY_AWARDED:
				AILog.Info("Event: Subsidy awarded");
				sube = AIEventSubsidyAwarded.Convert(e);
				subID = sube.GetSubsidyID();
				coID = AISubsidy.GetAwardedTo(subID);
				local status;
				if (coID == Me) {
					AILog.Info("Subsidy awarded to ME!!!");
					status = "won";
					this.subsidies.totals.won++;
				} else {
					AILog.Info("Event: Subsidy awarded to " + AICompany.GetName(coID));
					status = "lost";
					this.subsidies.totals.lost++;
				}
				if (subID in this.subsidies) {
					this.subsidies[subID].status = "won";
				}
				break;

			case AIEvent.ET_SUBSIDY_EXPIRED:
				AILog.Info("Event: Subsidy expired");
				sube = AIEventSubsidyExpired.Convert(e);
				subID = sube.GetSubsidyID();
				if (subID in this.subsidies) {
					delete this.subsidies[subID];
				}
				this.subsidies.totals.active--;
				this.subsidies.totals.inactive++;
				// TODO: evaluate and scale back service?
				break;

		}
	}

	function Handle_subsidy_offer(subID)
	{
		Debug("subsidy ID is " + subID);

		local bval = AISubsidy.IsValidSubsidy(subID);
		local awarded = AISubsidy.IsAwarded(subID);
		if (bval == false) {
			Debug("subsidy not valid, skipping");
			this.subsidies[subID] <- {
				status = "invalid",
			}
			this.subsidies.totals.total++;
			this.subsidies.totals.active--
			return;
		} else if (awarded == true) {
			local coID = AISubsidy.GetAwardedTo(subID);
			Debug("subsidy already awarded to " + AICompany.GetName(coID) + ", skipping");
			this.subsidies[subID] <- {
				status = "lost",
			}
			this.subsidies.totals.total++;
			return;
		}
		// check for expiration?

		if (subID in this.subsidies) {
			local status = this.subsidies[subID].status;
			if (status != "open") {
				AILog.Info(subID + " already seen.  Its status is " + status);
				return;
			}
		} else {
			this.subsidies[subID] <- {
				status = "open",
			}
			this.subsidies.totals.total++;
			this.subsidies.totals.active++;
		}

		local sdate = AISubsidy.GetExpireDate(subID);
		Debug("subsidy expires on " + sdate);

		local cargo = AISubsidy.GetCargoType(subID);
		Debug("cargo is " + cargo + " " + AICargo.GetCargoLabel(cargo));
		if (AICargo.IsValidCargo(cargo)) {
			Debug("cargo is valid");
		} else {
			Debug("cargo is NOT valid");
			this.subsidies[subID].status = "invalid";
			this.subsidies.totals.active--
			return;
		}

		/*
		local found_town = false;
		if (AISubsidy.GetSourceType(subID) == AISubsidy.SPT_TOWN) {
			tasks.append(BuildStopInTown(null, AISubsidy.GetSourceIndex(subID), cargo));
			Debug("no support for town subsidies yet");
			found_town = true;
		}
		if (AISubsidy.GetDestinationType(subID) == AISubsidy.SPT_TOWN) {
			tasks.append(BuildStopInTown(this, AISubsidy.GetDestinationIndex(subID), cargo));
			Debug("no support for town subsidies yet");
			found_town = true;
		}
		if (found_town == true) { return }
		*/
		
		// AISubsidy.SPT_INDUSTRY

		local consumer = AISubsidy.GetDestinationIndex(subID);
		local producer_info = {
			id = AISubsidy.GetSourceIndex(subID),
			type = AISubsidy.GetSourceType(subID),
		}
		local consumer_info = {
			id = AISubsidy.GetDestinationIndex(subID),
			type = AISubsidy.GetDestinationType(subID),
		}
		
		if (AIIndustry.IsBuiltOnWater(producer_info.id)) {
		} else {
			tasks.append(BuildTransferCargoLine(null, producer_info, consumer_info, cargo));
		}

		/*
		local producer = AISubsidy.GetSourceIndex(subID);
		local consumer = AISubsidy.GetDestinationIndex(subID);
		tasks.append(BuildNamedCargoLine(null, producer, consumer, cargo));
		*/
	}

}

class TransferStrategy extends Strategy {
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
