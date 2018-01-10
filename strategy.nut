
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
	TRUCK_MAX = 80;

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
			if (AITile.GetDistanceManhattanToTile(producer, consumer) <= TRUCK_MAX) {
				tasks.append(BuildTruckRoute(null, producer, consumer, cargo));
			} else {
				tasks.append(BuildNamedCargoLine(null, producer, consumer, cargo));
			}
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
			tasks.append(BuildShipRoute(null, obj_depot.depot, producer_info.location, obj_dock.dock, cargo));
		} else if (producer_info.type == AISubsidy.SPT_TOWN &&
			consumer_info.type == AISubsidy.SPT_TOWN &&
			AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {

			local towns = [
				producer_info.id,
				consumer_info.id
			];
			tasks.append(BuildBusRoute(null, towns, cargo));

		} else if (distance <= TRUCK_DISTANCE) {
			tasks.append(BuildTruckRoute(null, producer_info.location, consumer_info.location, cargo));
		} else {
			tasks.append(BuildNamedCargoLine(null, producer_info.id, consumer_info.id, cargo));
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

	constructor(population_min=500) {
		this.min = population_min;
		local cargoIDs = GenCargos();
		this.cargo = cargoIDs.PASS;
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

		this.busroute = BuildBusRoute(null, towns, cargo);
		tasks.append(this.busroute);
		RunSubTasks();
	}

	function Wake() {
		local stations = this.busroute.stations;
		local town, station;
		foreach (town,station in stations) {
			Debug("town=", town, " station=", station);
			local stationID = AIStation.GetStationID(station);
			local rating = GetRating(stationID);
			if (rating < 65) {
				Debug("Add another bus");
				this.busroute.AddBusAtStation(station);
			}
		}
	}

	function GetRating(stationID) {
		local rating = 100;
		local sname = AIStation.GetName(stationID);
		if (AIStation.HasCargoRating(stationID, cargo)) {
			rating = AIStation.GetCargoRating(stationID, cargo);
			Debug("rating at ", sname, " station is ", rating);
		} else {
			Debug("station ", sname, " has no rating");
		}
		return rating;
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
