// debug_level script=4

require("util.nut");
require("pathfinder.nut");
require("world.nut");
require("signs.nut");
require("task.nut");
require("finance.nut");
require("builder.nut");
require("planner.nut");

//require("route.nut");
require("guides.nut");
require("strategy.nut");
require("test.nut");

const MIN_DISTANCE =  30;
const MAX_DISTANCE = 100;
const MAX_BUS_ROUTE_DISTANCE = 40;
const INDEPENDENTLY_WEALTHY = 1000000;	// no longer need a loan

enum Direction {
	N, E, S, W, NE, NW, SE, SW
}

// counterclockwise
enum Rotation {
	ROT_0, ROT_90, ROT_180, ROT_270
}

enum SignalMode {
	NONE, FORWARD, BACKWARD
}

import("pathfinder.road", "RoadPathFinder", 4);

class FunAI extends AIController
{
	Me = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);

	guides = [];
	timer = 0;
	tasks = [];
	cargoIDs = {}; // populated by GenCargos()

	function Save() {
		return {};
	}

	function Load(version, data) {
		return {};
	}

	function Start()
	{
		Debug("Start() called");
		local NameBase = "Sub King Corp";
		if (!AICompany.SetName(NameBase)) {
			local i = 2;
			while (!AICompany.SetName(NameBase + " #" + i)) {
				i = i + 1;
			}
		}
		Debug("set company name to " + AICompany.GetName(Me));

		AICompany.SetAutoRenewStatus(true);
		AICompany.SetAutoRenewMonths(0);
		AICompany.SetAutoRenewMoney(0);
		
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		AIRail.SetCurrentRailType(AIRailTypeList().Begin());

		::COMPANY <- AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
		::TICKS_PER_DAY <- 37;
		::SIGN1 <- -1;
		::SIGN2 <- -1;
		::PAX <- GetPassengerCargoID();
		::MAIL <- GetMailCargoID();

		CheckGameSettings();

		GenCargos();

		this.guides = [
			VerySmallMapGuide(),
			BigCityRoutes(),
		];

		local guide;
		foreach (guide in this.guides) {
			Debug("guide: " + guide.desc);
			try {
				guide.Start();
			} catch (e) {
				Error("exception thrown");
			}
		}

		MainLoop();
	}

	function MainLoop() {
		local last_day = "";
		local cur_day;
		local date;

		while (true) {
			date = AIDate.GetCurrentDate();
			cur_day = AIDate.GetDayOfMonth(date);
			if (cur_day != last_day) {
				EndOfQuarter();
				last_day = cur_day;
			}
			Handle_events();
			Handle_timers();
			this.Sleep(TICKS_PER_DAY / 4);
		}
	}

	function Handle_events()
	{
		//Debug("Handle_events() called");
		while (AIEventController.IsEventWaiting()) {
			local e = AIEventController.GetNextEvent();
			Debug("this event occurred: " + e.GetEventType());
			local guide;
			foreach (guide in this.guides) {
				guide.Event(e);
			}
		}
	}
	
	function EndOfQuarter()
	{
		/*
		First quarter, Q1: 1 January – 31 March (90 days or 91 days in leap years)
		Second quarter, Q2: 1 April – 30 June (91 days)
		Third quarter, Q3: 1 July – 30 September (92 days)
		Fourth quarter, Q4: 1 October – 31 December (92 days)
		*/
		local date = AIDate.GetCurrentDate();
		local thisyear = AIDate.GetYear(date);
		local quarters = {
			q1 = AIDate.GetDate(thisyear, 3, 31),
			q2 = AIDate.GetDate(thisyear, 6, 30),
			q3 = AIDate.GetDate(thisyear, 9, 30),
			q4 = AIDate.GetDate(thisyear, 12, 31),
		};
		local q;
		foreach (q,_ in quarters) {
			if (quarters[q] == date) {
				Debug("New Quarter");
				CompanyStats();
				//RouteStats();
				//SubsidyStats();
			}
		}
	}

	function Handle_timers()
	{
		local s_tick = this.GetTick();
		if (this.timer > s_tick) {
			return;
		} else {
			this.timer = s_tick + (TICKS_PER_DAY);
		}

		local guide;
		foreach (guide in this.guides) {
			//Debug("guides " + guide.desc + ".Wake()");
			guide.Wake();
		}
	}

	function CompanyStats()
	{
		local curr, last;
		local qc = AICompany.CURRENT_QUARTER;
		local ql = AICompany.EARLIEST_QUARTER;

		Debug("my loan amount is ", AICompany.GetLoanAmount());
		Debug("max loan is ", AICompany.GetMaxLoanAmount());
		Debug("bank balance is ", AICompany.GetBankBalance(Me));

		curr = AICompany.GetQuarterlyIncome(Me, qc);
		last = AICompany.GetQuarterlyIncome(Me, ql);
		Debug("quarterly income: ", curr, "(", last, ")");

		curr = AICompany.GetQuarterlyExpenses(Me, qc);
		last = AICompany.GetQuarterlyExpenses(Me, ql);
		Debug("quarterly expenses: ", curr, "(", last, ")");

		curr = AICompany.GetQuarterlyCargoDelivered(Me, qc);
		last = AICompany.GetQuarterlyCargoDelivered(Me, ql);
		Debug("quarterly cargo delivered: ", curr, "(", last, ")");

		curr = AICompany.GetQuarterlyPerformanceRating(Me, qc);
		curr = AICompany.GetQuarterlyPerformanceRating(Me, ql);
		Debug("quarterly performance rating: ", curr, "(", last, ")");

		local infras = {
			rail    = AIInfrastructure.INFRASTRUCTURE_RAIL,
			signals = AIInfrastructure.INFRASTRUCTURE_SIGNALS,
			road    = AIInfrastructure.INFRASTRUCTURE_ROAD,
			canal   = AIInfrastructure.INFRASTRUCTURE_CANAL,
			station = AIInfrastructure.INFRASTRUCTURE_STATION,
			airport = AIInfrastructure.INFRASTRUCTURE_AIRPORT,
		}
		local name, val, ct;
		foreach (name, val in infras) {
			ct = AIInfrastructure.GetInfrastructurePieceCount(Me, val);
			Debug("total " + name + " infrastructure piece count: " + ct);

			ct = AIInfrastructure.GetMonthlyInfrastructureCosts(Me, val);
			Debug("monthly " + name + " infrastructure cost: " + ct);

			ct = AIInfrastructure.GetMonthlyInfrastructureCosts(Me, val);
			Debug("monthly " + name + " infrastructure cost: " + ct);
		}

		/*
		local roadtype = AIRoad.GetCurrentRoadType();
		local ct = AIInfrastructure.GetRoadPieceCount(Me, roadtype);
		Debug("road piece count: " + ct);

		local railtype = AIRail.GetCurrentRailType();
		ct = AIInfrastructure.GetRailPieceCount(Me, railtype);
		Debug("rail piece count: " + ct);
		*/

	}

	function CheckGameSettings() {
		local ok = true;
		ok = CheckSetting("construction.road_stop_on_town_road", 1,
			"Advanced Settings, Stations, Allow drive-through road stations on town owned roads") && ok;
		ok = CheckSetting("station.distant_join_stations", 1,
			"Advanced Settings, Stations, Allow to join stations not directly adjacent") && ok;
		
		if (ok) {
			Debug("Game settings OK");
		} else {
			throw "not compatible with current game settings.";
		}
	}
	
	function CheckSetting(name, value, description) {
		if (!AIGameSettings.IsValid(name)) {
			Warning("Setting " + name + " does not exist! this may not work properly.");
			return true;
		}
		
		local gameValue = AIGameSettings.GetValue(name);
		if (gameValue == value) {
			return true;
		} else {
			Warning(name + " is " + (gameValue ? "on" : "off"));
			Warning("You can change this setting under " + description);
			return false;
		}
	}

}

/* :vim set ai: source sq.vim: syn on: */
