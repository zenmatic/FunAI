
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
			subtasks.append(BuildTruckDepot(this, producer));
		}
		subtasks.extend([
			BuildTruckStation(this, producer),
			BuildTruckStation(this, consumer),
			BuildRoad(this, producer, consumer),
			BuildRoad(this, producer, depot),
			BuildTruck(this, depot, producer, consumer, cargo),
		]);
	}
}

class BuildTruckStation extends Task {
	location = null;
	ttype = null; // transport type

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
		//local stationtype = AIStation.STATION_NEW;
		local stationtype = AIStation.STATION_JOIN_ADJACENT;
		local area = AITileList();
		SafeAddRectangle(area, location, 1);
		area.RemoveValue(location);
		local ret = AIRoad.BuildRoadStation(loc, loc+1, stype, stationtype); 
		Debug("build stop at ", loc);
		if (ret == false) { PrintError() }
		Debug("ret=", ret);
		return ret;

	}

}

class BuildBusStation extends Task {

	// AIRoad.ROADVEHTYPE_TRUCK or AIRoad.ROADVEHTYPE_BUS
	constructor(parentTask, location, ttype = AIRoad.ROADVEHTYPE_BUS) {
		BuildTruckStation.constructor(parentTask, location, ttype);
	}
	
	function _tostring() {
		return "BuildBusStation";
	}
}

class BuildTruckDepot extends Task {

	location = null;
	depot = null;

	constructor(parentTask, l) {
		Task.constructor(parentTask, null);
		location = l;
	}
	
	function _tostring() {
		return "BuildTruckDepot";
	}

	function Run() {
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
