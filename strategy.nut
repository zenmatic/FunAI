
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
					}
				} else {
					Error("Unexpected error");
					return;
				}
			}
		}
	}

}

class StrategyFlex extends Strategy {
	desc = "strategy class with options";
	options = {};
	startdate = null;
	intervaldate = null;

	constructor(opts) {
		startdate = intervaldate = AIDate.GetCurrentDate();
		ParseOptions(opts);
	}

	function ParseOptions(opts) {
		// defaults
		options = {
			maxdistance = 0,
			mindistance = 0,
			maxroutes = 10,
			interval = 1,
			delay = 0,
		};

		local opt;
		foreach (opt,_ in opts) {
			if (opt in options) {
				options[opt] = opts[opt];
			} else {
				options[opt] <- opts[opt];
			}
		}
	}

	function IsDelayOver() {
		local now = AIDate.GetCurrentDate();
		local min = startdate + options.delay;
		if (now < min) {
			local diff = min - now;
			Debug(diff, " days left til delay is done");
			return false;
		}
		return true;
	}

	// check and reset
	function IsIntervalOver() {
		local now = AIDate.GetCurrentDate();
		local min = intervaldate + options.interval;
		if (now < min) {
			local diff = min - now;
			Debug(diff, " days left til next interval");
			return false;
		}
		intervaldate = now;
		return true;
	}
}

class SimpleSuppliesStrategy extends StrategyFlex {
	desc = "make supply routes which are somewhat close together";
	TRUCK_MAX = 40;
	seenroutes = [];
	routes = [];

	constructor(opts) {
		StrategyFlex.constructor(opts);

		routes = [];
		seenroutes = [];
	}

	function Start() {
		if (!IsDelayOver()) { return }
		DoNewRoute();
	}

	function Wake() {
		if (!IsDelayOver()) { return }
		if (NeedNewRoute()) {
			DoNewRoute();
		} else {
			local route;
			foreach (route in routes) {
				route.Wake();
			}
		}
	}

	function NeedNewRoute() {
		if (routes.len() >= options.maxroutes) {
			Debug("reached max routes of ", options.maxroutes);
			return false;
		}
		return IsIntervalOver();
	}

	function DoNewRoute() {

		local routelist = FindSupplyRoutes();
		if (routelist.len() > 0) {
			local r = routelist.pop();
			seenroutes.append(r);
			local cargo = r[0];
			local producer = AIIndustry.GetLocation(r[1]);
			local consumer = AIIndustry.GetLocation(r[2]);
			local locations = [producer, consumer];
			local obj = RateBasedRoute(null, locations, cargo);
			routes.append(obj);
			tasks.append(obj);
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
					} else if (dist >= options.mindistance && dist <= options.maxdistance) {
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
		foreach (r in this.seenroutes) {
			if (r[0] == cargo && r[1] == pID && r[2] == aID && r[3] == dist) {
				return true;
			}
		}
		return false;
	}
}

class AuxSuppliesStrategy extends SimpleSuppliesStrategy {
	desc = "supply towns with food or goods from existing stations";

	function DoNewRoute() {

		local routelist = FindSupplyRoutes();
		if (routelist.len() > 0) {
			local r = routelist.pop();
			local cargo = r[0];
			local producer = r[1];
			local townID = r[2];

			local bobj = BuildStopInTown(null, townID, cargo);
			bobj.Run();
			if (bobj.station == null) {
				return;
			}
			local consumer = bobj.station;

			seenroutes.append(r);
			local locations = [producer, consumer];
			local obj = RateBasedRoute(null, locations, cargo);
			routes.append(obj);
			tasks.append(obj);
		}
	}

	function IsCargoGood(cargo) {
		local te = AICargo.GetTownEffect(cargo);
		if (AICargo.IsValidTownEffect(te)) {
			//Debug("is a valid town effect");
			if (te == AICargo.TE_GOODS) {
				//Debug("towns are effected by goods");
				return true;
			} else if (te == AICargo.TE_FOOD) {
				//Debug("towns are effected by food");
				return true;
			}
		}
		return false;
	}

	function FindSupplyRoutes() {
		local routelist = []; // pID, aID, distance between them

		foreach (cargo in GenCargos()) {
			if (!IsCargoGood(cargo)) { continue }

			local cname = AICargo.GetCargoLabel(cargo);
			//Debug("looking for aux industries with cargo ", cname);
			local industries = AIIndustryList_CargoProducing(cargo);
			//Debug("found ", industries.Count(), " of them");
			foreach (industry,_ in industries) {
				local pID = FindStationNearIndustry(industry);
				if (pID == null) { continue }
				//Debug("Found station near ", AIIndustry.GetName(industry));
				local stationloc = AIStation.GetLocation(pID);
				local townID = AITile.GetClosestTown(stationloc);
				local dist = AITown.GetDistanceManhattanToTile(townID, stationloc);
				//Debug("stationloc=", stationloc, " townID=", townID, " dist=", dist);
				if (RouteTaken(cargo, pID, townID)) {
					continue;
				} else if (dist >= options.mindistance && dist <= options.maxdistance) {
					local arr = [ cargo, stationloc, townID, dist ];
					routelist.append(arr);
				}
			}
		}
		return routelist;
	}

	function FindStationNearIndustry(industryID) {
		local tiles = AITileList_IndustryProducing(industryID, 3);
		//Debug("Count is ", tiles.Count());
		local tile;
		/*
		foreach (tile in tiles) {
			AISign.BuildSign(tile, "X");
		}
		*/
		tiles.Valuate(AIRoad.IsRoadStationTile);
		tiles.KeepValue(1);
		//Debug("Count after IsRoadStationTile() is ", tiles.Count());
		if (tiles.Count() < 1) {
			//Debug("no stations found");
			return null;
		}

		local stype = AIStation.STATION_TRUCK_STOP;
		local stations = AIStationList(stype);
		//Debug("stations.Count() is ", stations.Count());
		local station;
		foreach (station,_ in stations) {
			local tile;
			local stationloc = AIStation.GetLocation(station);
			foreach (tile,_ in tiles) {
				if (tile == stationloc) {
					return station;
				}
			}
		}
		return null;
	}

	function RouteTaken(cargo, pID, townID) {
		local r;
		foreach (r in this.seenroutes) {
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

	function Start() { Wake(); }

	function Wake() {
		local Me = this.companyID;
		local intval = AICompany.GetLoanInterval();
		local max = AICompany.GetMaxLoanAmount();
		local balance = AICompany.GetBankBalance(Me);
		//Debug("interval=" + intval + " max=" + max + " balance=" + balance);
		local loan = max;
		//Debug("I want to get a loan of " + loan);
		local ret = AICompany.SetMinimumLoanAmount(loan);
		balance = AICompany.GetBankBalance(Me);
		//Debug("ret=" + ret + " my balance is " + balance);
	}
}

class ZeroLoanStrategy extends LoanStrategy {
	desc = "return all the loan money I can";

	function Start() { Wake(); }

	function Wake() {
		local Me = this.companyID;
		local intval = AICompany.GetLoanInterval();
		local balance = AICompany.GetBankBalance(Me);
		local currloan = AICompany.GetLoanAmount();
		//Debug("current loan is " + currloan);
		//Debug("interval=" + intval + " currloan=" + currloan + " balance=" + balance);
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
		//Debug("I want set my loan to " + loan);
		local ret = AICompany.SetLoanAmount(loan);
		//Debug("ret=" + ret);
	}
}

class ChooStrategy extends Strategy {
	desc = "choo's strategy";
	function Start() {
		tasks.append(BuildNewNetwork(null));
	}
}

class SubStrategy extends Strategy {

	// if close, use a bus
	TRUCK_DISTANCE = 80;

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

	function Start() { Wake(); }

	function Wake() {
		local sublist = AISubsidyList();
		local subID = 0;
		foreach (subID,_ in sublist) {
			Handle_subsidy_offer(subID);
		}

		local route;
		foreach (route in this.routes) {
			local station;
			foreach (station in route.stations) {
				local stationID = AIStation.GetStationID(station);
				local rating = GetRating(stationID, route.cargo);
				if (rating < 50) {
					Debug("Add another bus");
					route.AddVehicleAtStation(station);
				}
			}
		}
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

			/*
			case AIEvent.ET_SUBSIDY_OFFER:
				AILog.Info("Event: Subsidy offered");
				sube = AIEventSubsidyOffer.Convert(e);
				subID = sube.GetSubsidyID();
				Handle_subsidy_offer(subID);
				break;
			*/

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
			//Debug("subsidy", subID, "status is", subsidies[subID].status);
			return;
		} else {
			this.subsidies[subID] <- {
				status = "open",
			}
			//Debug("subsidy", subID, "status is", subsidies[subID].status);
			this.subsidies.totals.total++;
			this.subsidies.totals.active++;
		}
		local status = this.subsidies[subID].status;

		local sdate = AISubsidy.GetExpireDate(subID);
		Debug("subsidy expires on", sdate);

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

		local getinfo = function(subID, indexfunc, typefunc) {
			local id = indexfunc(subID);
			local type = typefunc(subID);
			local name = (type == AISubsidy.SPT_TOWN) ? AITown.GetName(id) : AIIndustry.GetName(id);
			// AISubsidy.SPT_INDUSTRY or AISubsidy.SPT_TOWN
			local location = (type == AISubsidy.SPT_TOWN) ? AITown.GetLocation(id) : AIIndustry.GetLocation(id);
			return {
				id = id,
				type = type,
				name = name,
				location = location,
			};
		}

		local producer_info = getinfo(subID, AISubsidy.GetSourceIndex, AISubsidy.GetSourceType);
		local consumer_info = getinfo(subID, AISubsidy.GetDestinationIndex, AISubsidy.GetDestinationType);
		local distance = AITile.GetDistanceManhattanToTile(producer_info.location, consumer_info.location);
		
		if (AIIndustry.IsBuiltOnWater(producer_info.id)) {
			local obj_depot = BuildWaterDepotBetween(null, producer_info.location, consumer_info.location);
			local obj_dock = BuildDock(null, consumer_info.location);
			tasks.extend([
				obj_depot,
				obj_dock,
			]);
			RunTasks();
			local r = BuildShipRoute(null, obj_depot.depot, producer_info.location, obj_dock.dock, cargo);
			routes.append(r);
			tasks.append(r);
		} else if (producer_info.type == AISubsidy.SPT_TOWN && consumer_info.type == AISubsidy.SPT_TOWN) {

			local towns = [
				producer_info.id,
				consumer_info.id
			];
			local r = BuildTownRoute(null, towns, cargo);
			routes.append(r);
			tasks.append(r);
		} else if (distance <= TRUCK_DISTANCE) {
			local locs = [ producer_info.location, consumer_info.location ];
			local r = BuildTruckRoute(null, locs, cargo);
			routes.append(r);
			tasks.append(r);
		} else {
			local r = BuildNamedCargoLine(null, producer_info.id, consumer_info.id, cargo);
			routes.append(r);
			tasks.append(r);
		}
	}
}

// probably works best on small maps
class BusesToEveryTown extends Strategy {
	desc = "bus stop in every town";

	function Start() {
		local l = AITownList();
		// need to sort by distance or location
		Debug("l.Count()=", l.Count());
		local towns = ListToArray(l);
		Debug("towns.len()=", towns.len());
		local cargoIDs = GenCargos();
		local cargo = cargoIDs.PASS;
		tasks.append(BuildBusRoute(null, towns, cargo));
	}
}

class BusesToPopularTowns extends Strategy {
	desc = "bus stop in every town with a threshold population";
	min = null;
	busroute = null;
	cargo = null;
	throttles = null;

	constructor(population_min=500) {
		this.min = population_min;
		local cargoIDs = GenCargos();
		this.cargo = cargoIDs.PASS;

		throttles = {};
	}

	function Start() {
		local tlist = AITownList();
		tlist.Valuate(AITown.GetPopulation);
		tlist.KeepAboveValue(min);
		local biggest = tlist.Begin();
		tlist.RemoveItem(biggest);
		tlist.Valuate(AITown.GetDistanceManhattanToTile, biggest);
		tlist.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		local towns = [ biggest ];
		local arr = ListToArray(tlist);
		towns.extend(arr);
		local t;
		foreach (t in towns) {
			local tname = AITown.GetName(t);
			local pop = AITown.GetPopulation(t);
			Debug(tname," ", pop);
		}

		this.busroute = BuildTownRoute(null, towns, cargo);
		tasks.append(this.busroute);
	}

	function Wake() {
		local stations = this.busroute.stations;
		local town, station;
		foreach (town,station in stations) {
			//Debug("town=", town, " station=", station);
			local stationID = AIStation.GetStationID(station);
			local rating = GetRating(stationID, cargo);
			if (rating < 60) {
				Debug("station rating is ", rating, ". Add another bus");
				if (CanAddBus(stationID)) {
					this.busroute.AddBusAtStation(station);
				} else {
					Debug("throttling, no bus at this time");
				}
			}
		}
	}

	function CanAddBus(stationID) {
		local now = AIController.GetTick();
		local future = now + (TICKS_PER_DAY * 15);
		if (stationID in throttles) {
			local next_tick = throttles[stationID];
			if (next_tick > now) {
				throttles[stationID] = future;
				return true;
			}
		} else {
			throttles[stationID] <- future;
			return true;
		}
		return false;
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

class ExpandTowns extends Strategy {
	desc = "expand towns by adding streets";
	minpopulation = 0;
	maxpopulation = 1000;
	interval = 0;
	lasttime = 0;

	// interval is a new route every N days
	constructor(min=1, max=1000, interval=30) {
		this.maxpopulation = max;
		this.minpopulation = min;
		this.interval = interval;
	}

	function GoTime() {
		local now = AIDate.GetCurrentDate();
		local min = lasttime + interval;
		if (now < min) {
			local diff = min - now;
			//Debug(diff, " days left til next interval");
			return false;
		}
		lasttime = now;
		return true;
	}

	function Wake() {
		if (!GoTime()) { return }

		local towns = AITownList();
		towns.Valuate(AITown.GetPopulation);
		towns.KeepBetweenValue(minpopulation, maxpopulation);

		local valfunc = function(tile, townID) {
			return AITown.IsWithinTownInfluence(townID, tile);
		}

		local town;
		foreach (town,_ in towns) {
			//Debug("try to expand ", AITown.GetName(town));
			local tiles = AITileList();
			SafeAddRectangle(tiles, AITown.GetLocation(town), 40);
			tiles.Valuate(valfunc, town);
			tiles.KeepValue(1);
			local ret = CrossStreet(tiles);
		}
	}

	function CrossStreet(tiles) {
		tiles.Valuate(AIRoad.IsRoadTile);
		tiles.KeepValue(1);
		tiles.Valuate(AIMap.GetTileX);
		tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		local tile;
		foreach (tile,_ in tiles) {
			local ret = CrossX(tile);
			if (ret) { return true }
			local ret = CrossY(tile);
			if (ret) { return true }
		}
		return false;
	}

	function CrossX(start) {
		local startx = AIMap.GetTileX(start);
		local y = AIMap.GetTileY(start);

		//local signs = [];
		//local signID = AISign.BuildSign(start, "S");
		//signs.append(signID);

		local succ = true;
		local i, tile;
		for (i=1; i < 4; i++) {
			local x = startx + i;
			tile = AIMap.GetTileIndex(x,y);
			if (!AIMap.IsValidTile(tile)) {
				succ = false;
				break;
			}
			//local signID = AISign.BuildSign(tile, ""+i);
			//signs.append(signID);
			if (!AITile.IsBuildable(tile) ||
				AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
				succ = false;
				break;
			}
		}
		local end = AIMap.GetTileIndex(startx + i, y);
		//local sign;
		//foreach (sign in signs) {
			//AISign.RemoveSign(sign);
		//}
		if (succ && AIMap.IsValidTile(end) && AIRoad.IsRoadTile(end)) {
			return AIRoad.BuildRoad(start, end);
		}
		return false;
	}

	function CrossY(start) {
		local starty = AIMap.GetTileY(start);
		local x = AIMap.GetTileX(start);

		//local signs = [];
		//local signID = AISign.BuildSign(start, "S");
		//signs.append(signID);

		local succ = true;
		local i, tile;
		for (i=1; i < 4; i++) {
			local y = starty + i;
			tile = AIMap.GetTileIndex(x,y);
			if (!AIMap.IsValidTile(tile)) {
				succ = false;
				break;
			}
			//local signID = AISign.BuildSign(tile, ""+i);
			//signs.append(signID);
			if (!AITile.IsBuildable(tile) ||
				AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
				succ = false;
				break;
			}
		}
		local end = AIMap.GetTileIndex(x, starty + i);
		//local sign;
		//foreach (sign in signs) {
			//AISign.RemoveSign(sign);
		//}
		if (succ && AIMap.IsValidTile(end) && AIRoad.IsRoadTile(end)) {
			return AIRoad.BuildRoad(start, end);
		}
		return false;
	}

	function TryCrossStreet(tile1, tile2) {
		local x1 = AIMap.GetTileX(tile1);
		local x2 = AIMap.GetTileX(tile2);
		if (abs(x1 - x2) != 4) { return false }
		local start, end;
		if (x1 < x2) {
			start = tile1;
			end = tile2;
		} else {
			start = tile2;
			end = tile1;
		}
		local startx = AIMap.GetTileX(start);
		local y = AIMap.GetTileY(start);
		local succ = true;
		local signs = [];
		local signID = AISign.BuildSign(start, "S");
		signs.append(signID);
		local signID = AISign.BuildSign(end, "E");
		signs.append(signID);
		local i;
		for (i=1; i < 4; i++) {
			local x = startx + i;
			local tile = AIMap.GetTileIndex(x,y);
			local signID = AISign.BuildSign(tile, ""+i);
			signs.append(signID);
			if (!AITile.IsBuildable(tile) ||
				AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
				succ = false;
				break;
			}
		}
		local sign;
		foreach (sign in signs) {
			AISign.RemoveSign(sign);
		}
		if (succ) {
			return AIRoad.BuildRoad(start, end);
		}

		return false;
	}
}
