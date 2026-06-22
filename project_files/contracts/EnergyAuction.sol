// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

contract EnergyAuction is AutomationCompatibleInterface {

	address payable deployer;

	AggregatorV3Interface public priceFeed;
	uint public interval;
	uint public lastTimeStamp;

	uint indics;
	uint indicb;
	uint indicm;
	uint period;
	uint ethPriceInCents;
	string ethPrice;

	event NewMember(address payable memberaddr, uint id);
	event InsufficientContractBalance(string notice);
	event EnergyTransfer(uint source, uint destination, uint kWhs);
	event TransactionsCompleted();
	event PriceUpdated(uint ethPriceInCents);

	struct Participant {
		uint id;
		uint amount;
		uint differentialcost;
		uint[] neighbors;
	}

	mapping(address => Participant) sellers;
	mapping(address => Participant) buyers;
	mapping(address => Participant) members;

	address payable[] selleraddresses;
	address payable[] buyeraddresses;
	address payable[] memberaddresses;

	constructor (address _priceFeed, uint _interval) {
		deployer = payable(msg.sender);
		priceFeed = AggregatorV3Interface(_priceFeed);
		interval = _interval;
	}

	function initiate () public {
		require(msg.sender == deployer, "Only the deployer can make this call");
		require(period == 0, "Already initiated");
		_updatePrice();
		lastTimeStamp = block.timestamp;
		period = 1;
	}

	function checkUpkeep (bytes calldata /* checkData */)
		external
		view
		override
		returns (bool upkeepNeeded, bytes memory performData)
	{
		upkeepNeeded = (period > 0) && ((block.timestamp - lastTimeStamp) >= interval);
		performData = "";
	}

	function performUpkeep (bytes calldata /* performData */) external override {
		require((period > 0) && ((block.timestamp - lastTimeStamp) >= interval), "Upkeep not needed");
		lastTimeStamp = block.timestamp;
		_updatePrice();
		period += 1;
		if (period > 1) {
			transferring();
		}
	}

	function _updatePrice () internal {
		(, int256 answer, , , ) = priceFeed.latestRoundData();
		require(answer > 0, "Invalid feed answer");
		uint8 dec = priceFeed.decimals();
		require(dec >= 2, "Unexpected feed decimals");
		ethPriceInCents = uint(answer) / (10 ** (uint(dec) - 2));
		require(ethPriceInCents > 0, "Price below cent resolution");
		ethPrice = _formatCents(ethPriceInCents);
		emit PriceUpdated(ethPriceInCents);
	}

	function showethPrice () public view returns (string memory) {
		return ethPrice;
	}

	function ethPriceCents () public view returns (uint) {
		return ethPriceInCents;
	}

	function weiconversion (string memory s) public view returns(uint) {
		require(ethPriceInCents > 0, "Price not set yet");
		bytes memory byt = bytes(s);
		require(byt.length > 0, "Empty input");
		uint d;
		bool seenDot;
		for (uint i = 0; i < byt.length; i++) {
			uint8 c = uint8(byt[i]);
			if (c == 46) { // '.'
				require(!seenDot, "Invalid input, only numbers and dot character are allowed!");
				seenDot = true;
			} else {
				require((c >= 48) && (c <= 57), "Invalid input, only numbers and dot character are allowed!");
				if (seenDot) {
					d++;
				}
			}
		}
		require(d <= 2, "At most 2 decimal places are allowed!");
		uint p = parseInt(s, d);
		uint temp = uint(10 ** 18) / ethPriceInCents;
		uint priceinWei = (p * temp) * uint(10 ** (2 - d));
		return priceinWei;
	}

	function participating (uint _identifier, uint[] memory _neighbors) public {
		require(_identifier != 0, "0 cannot be id");
		require(period > 0, "Cannot participate yet");
		uint count;
		bool check;
		uint l = _neighbors.length;
		for (uint i=0; i<indicm; i++) {
			if (msg.sender == memberaddresses[i]) {
				members[memberaddresses[i]].id = _identifier;
				members[memberaddresses[i]].neighbors = _neighbors;
				check = true;
			}
			else {
				require(members[memberaddresses[i]].id != _identifier, "Id must be unique.");
			}
			for (uint j=0; j<l; j++) {
				if (_neighbors[j] == members[memberaddresses[i]].id) {
					require(_neighbors[j] != _identifier, "You should choose a different id!");
					members[memberaddresses[i]].neighbors.push(_identifier);
					count += 1;
				}
			}
		}
		require(count == l, "The member and the neighbors need to be connected to the network");
		if (check != true) {
			members[msg.sender].id = _identifier;
			members[msg.sender].neighbors = _neighbors;
			memberaddresses.push(payable(msg.sender));
			indicm = memberaddresses.length;
			emit NewMember(payable(msg.sender),_identifier);
		}
	}

	function withdrawing () public {
		uint ind = members[msg.sender].id;
		uint l;
		for (uint i=0; i<indicm; i++) {
			l = members[memberaddresses[i]].neighbors.length;
			for (uint j=0; j<l; j++) {
				if (ind == members[memberaddresses[i]].neighbors[j]) {
					delete members[memberaddresses[i]].neighbors[j];
				}
			}
			if (msg.sender == memberaddresses[i]) {
				for (uint j=i; j<indicm-1; j++){
					memberaddresses[j] = memberaddresses[j + 1];
				}
			}
		}
		memberaddresses.pop();
		indicm = memberaddresses.length;
	}

	function showmembers () public view returns (address payable[] memory) {
		return memberaddresses;
	}

	modifier entry_validation (uint _identifier) {
		bool check;
		for (uint i=0; i<indicm; i++) {
			if ((msg.sender == memberaddresses[i]) && (_identifier == members[memberaddresses[i]].id)) {
				check = true;
			}
		}
		require(check == true, "Invalid entry!");
		_;
	}

	function offering (uint _identifier, uint _availableamount, string memory _priceperkWh) entry_validation(_identifier) public {
		for (uint i=0; i<indics; i++) {
			if (msg.sender == selleraddresses[i]) {
				for (uint j=i; j<indics-1; j++){
					selleraddresses[j] = selleraddresses[j + 1];
				}
				selleraddresses.pop();
				break;
			}
		}
		sellers[msg.sender].id = _identifier;
		sellers[msg.sender].amount = _availableamount;
		uint price = weiconversion(_priceperkWh);
		sellers[msg.sender].differentialcost = price;
		selleraddresses.push(payable(msg.sender));
		indics = selleraddresses.length;
		for (uint i=0; i<indics; i++) { //sorting in ascending order
			if (sellers[selleraddresses[i]].differentialcost > price) {
				for (uint j=indics-1; j>i; j--) {
					selleraddresses[j] = selleraddresses[j-1];
				}
				selleraddresses[i] = payable(msg.sender);
				break;
			}
		}
	}

	function buying (uint _identifier, uint _requisiteamount, string memory _priceperkWh) entry_validation(_identifier) public payable {
		uint price = weiconversion(_priceperkWh);
		require((msg.value == _requisiteamount * price) || (msg.value > _requisiteamount * price), "You need to add the proper amount of ETH!");
		for (uint i=0; i<indicb; i++) {
			if (msg.sender == buyeraddresses[i]) {
				for (uint j=i; j<indicb-1; j++){
					buyeraddresses[j] = buyeraddresses[j + 1];
				}
				buyeraddresses.pop();
				break;
			}
		}
		buyers[msg.sender].id = _identifier;
		buyers[msg.sender].amount = _requisiteamount;
		buyers[msg.sender].differentialcost = price;
		buyeraddresses.push(payable(msg.sender));
		indicb = buyeraddresses.length;
		for (uint i=0; i<indicb; i++) { //sorting in ascending order
			if (buyers[buyeraddresses[i]].differentialcost > price) {
				for (uint j=indicb-1; j>i; j--) {
					buyeraddresses[j] = buyeraddresses[j-1];
				}
				buyeraddresses[i] = payable(msg.sender);
				break;
			}
		}
	}

	function transferring () internal {
		if (indicb == 0 || indics == 0) {
			delete selleraddresses;
			delete buyeraddresses;
			indicb = 0;
			indics = 0;
			emit TransactionsCompleted();
			return;
		}
		uint gain;
		uint price;
		uint quantity;
		uint sum;
		uint startprice;
		uint temp;
		for (uint i = indicb; i > 0; i--) {
			uint bi = i - 1;
			sum = 0;
			startprice = buyers[buyeraddresses[bi]].amount * buyers[buyeraddresses[bi]].differentialcost;
			for (uint j=0; j<indics; j++) {
				if (sellers[selleraddresses[j]].differentialcost > buyers[buyeraddresses[bi]].differentialcost) {
					break;
				}
				quantity = sellers[selleraddresses[j]].amount;
				if (buyers[buyeraddresses[bi]].amount > sellers[selleraddresses[j]].amount){
					buyers[buyeraddresses[bi]].amount -= sellers[selleraddresses[j]].amount;
					sellers[selleraddresses[j]].amount = 0;
				}
				else if (buyers[buyeraddresses[bi]].amount == sellers[selleraddresses[j]].amount) {
					buyers[buyeraddresses[bi]].amount = 0;
					sellers[selleraddresses[j]].amount = 0;
				}
				else {
					sellers[selleraddresses[j]].amount -= buyers[buyeraddresses[bi]].amount;
					buyers[buyeraddresses[bi]].amount = 0;
				}
				quantity -= sellers[selleraddresses[j]].amount;
				emit EnergyTransfer(sellers[selleraddresses[j]].id,buyers[buyeraddresses[bi]].id,quantity);
				price = (sellers[selleraddresses[j]].differentialcost+buyers[buyeraddresses[bi]].differentialcost)*quantity*50;
				gain += price - quantity * sellers[selleraddresses[j]].differentialcost * 100;
				sum += price;
				price = 999 * price / 1000;
				(bool sellerPaid, ) = selleraddresses[j].call{value: price / 100}("");
				require(sellerPaid, "Seller payout failed");
				if (buyers[buyeraddresses[bi]].amount == 0) {
					break;
				}
			}
			startprice -= buyers[buyeraddresses[bi]].differentialcost * buyers[buyeraddresses[bi]].amount;
			gain += startprice * 100 - sum;
			temp = 999 * (startprice * 100 - sum) / 1000;
			(bool buyerPaid, ) = buyeraddresses[bi].call{value: temp / 100}("");
			require(buyerPaid, "Buyer refund failed");
		}
		uint houseshare = 1000000000000000000 + gain / 1000; //the share of the deployer x100
		(bool housePaid, ) = deployer.call{value: houseshare / 100}("");
		require(housePaid, "House payout failed");
		emit TransactionsCompleted();
		delete selleraddresses;
		delete buyeraddresses;
		indicb = 0;
		indics = 0;
	}

	// --- string helpers (ported from the old Provable utility library) ---

	function parseInt (string memory _a, uint _b) internal pure returns (uint _parsedInt) {
		bytes memory bresult = bytes(_a);
		uint mint = 0;
		bool decimals = false;
		for (uint i = 0; i < bresult.length; i++) {
			if ((uint(uint8(bresult[i])) >= 48) && (uint(uint8(bresult[i])) <= 57)) {
				if (decimals) {
					if (_b == 0) {
						break;
					} else {
						_b--;
					}
				}
				mint *= 10;
				mint += uint(uint8(bresult[i])) - 48;
			} else if (uint(uint8(bresult[i])) == 46) {
				decimals = true;
			}
		}
		if (_b > 0) {
			mint *= 10 ** _b;
		}
		return mint;
	}

	function _uint2str (uint _i) internal pure returns (string memory) {
		if (_i == 0) {
			return "0";
		}
		uint j = _i;
		uint len;
		while (j != 0) {
			len++;
			j /= 10;
		}
		bytes memory bstr = new bytes(len);
		uint k = len;
		while (_i != 0) {
			k -= 1;
			bstr[k] = bytes1(uint8(48 + _i % 10));
			_i /= 10;
		}
		return string(bstr);
	}

	function _formatCents (uint _cents) internal pure returns (string memory) {
		uint whole = _cents / 100;
		uint frac = _cents % 100;
		string memory fracStr = frac < 10
			? string(abi.encodePacked("0", _uint2str(frac)))
			: _uint2str(frac);
		return string(abi.encodePacked(_uint2str(whole), ".", fracStr));
	}

	receive() external payable {} //needed for adding funds to the contract via web3.js
}
