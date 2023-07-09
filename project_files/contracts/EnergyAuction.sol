pragma solidity ^0.5.16;

import "./usingProvable.sol";

contract EnergyAuction is usingProvable {

	address payable deployer;
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

	constructor () public {
		OAR = OracleAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);
		deployer = msg.sender;
	}

	function initiate () public {
		require(msg.sender == deployer, "Only the deployer can make this call");
		if (period == 0) {
			provable_query("URL","json(https://api.kraken.com/0/public/Ticker?pair=ETHUSD).result.XETHZUSD.c.0");
			period += 1;
		}
	}

	function newCycle () internal {
		if (provable_getPrice("URL") <= address(this).balance) {
			provable_query(900,"URL","json(https://api.kraken.com/0/public/Ticker?pair=ETHUSD).result.XETHZUSD.c.0",500000);
			//15 minute time interval, 500000 gas limit
			period += 1;
		}
		else {
			emit InsufficientContractBalance("You need to add some ETH to the contract!"); //gas price * gas limit
		}
	}

	function __callback (bytes32 _queryID, string memory _result, bytes memory _proof) public {
		require(msg.sender == provable_cbAddress());
		ethPriceInCents = parseInt(_result, 2);
		ethPrice = _result;
		if (period > 1) {
			transferring();
		}
		newCycle();
	}

	function showethPrice () public view returns (string memory) {
		return ethPrice;
	}

	function weiconversion (string memory s) public view returns(uint) {
		bytes memory byt = bytes(s);
		uint d;
		bool check = true;
		for (uint i=byt.length-1; int(i)>-1; i--) {
			if (uint(uint8(byt[i])) == 46) {
				d = byt.length-i-1;
			}
			if (((uint(uint8(byt[i])) != 46) && (uint(uint8(byt[i])) < 48)) || (uint(uint8(byt[i])) > 57)) {
				check = false;
			}
		}
		require(check == true, "Invalid input, only numbers and dot character are allowed!");
		uint p = parseInt(s,d);
		uint temp = uint(10 ** 18) / ethPriceInCents;
		uint priceinWei = (p * temp) * uint(10 ** (2-d));
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
			indicm = memberaddresses.push(msg.sender);
			emit NewMember(msg.sender,_identifier);
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
		indics = selleraddresses.push(msg.sender);
		for (uint i=0; i<indics; i++) { //sorting in ascending order
			if (sellers[selleraddresses[i]].differentialcost > price) {
				for (uint j=indics-1; j>i; j--) {
					selleraddresses[j] = selleraddresses[j-1];
				}
				selleraddresses[i] = msg.sender;
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
		indicb = buyeraddresses.push(msg.sender);
		for (uint i=0; i<indicb; i++) { //sorting in ascending order
			if (buyers[buyeraddresses[i]].differentialcost > price) {
				for (uint j=indicb-1; j>i; j--) {
					buyeraddresses[j] = buyeraddresses[j-1];
				}
				buyeraddresses[i] = msg.sender;
				break;
			}
		}
	}

	function transferring () internal {
		uint gain;
		uint price;
		uint quantity;
		uint sum;
		uint startprice;
		uint temp;
		uint oraclefunds = uint(10000000000000000) / (indicb + indics);
		for (uint i=indicb-1; int(i)>-1; i--) {
			sum = 0;
			startprice = buyers[buyeraddresses[i]].amount * buyers[buyeraddresses[i]].differentialcost;
			for (uint j=0; j<indics; j++) {
				if (sellers[selleraddresses[j]].differentialcost > buyers[buyeraddresses[i]].differentialcost) {
					break;
				}
				quantity = sellers[selleraddresses[j]].amount;
				if (buyers[buyeraddresses[i]].amount > sellers[selleraddresses[j]].amount){
					buyers[buyeraddresses[i]].amount -= sellers[selleraddresses[j]].amount;
					sellers[selleraddresses[j]].amount = 0;
				}
				else if (buyers[buyeraddresses[i]].amount == sellers[selleraddresses[j]].amount) {
					buyers[buyeraddresses[i]].amount = 0;
					sellers[selleraddresses[j]].amount = 0;
				}
				else {
					sellers[selleraddresses[j]].amount -= buyers[buyeraddresses[i]].amount;
					buyers[buyeraddresses[i]].amount = 0;
				}
				quantity -= sellers[selleraddresses[j]].amount;
				emit EnergyTransfer(sellers[selleraddresses[j]].id,buyers[buyeraddresses[i]].id,quantity);
				price = (sellers[selleraddresses[j]].differentialcost+buyers[buyeraddresses[i]].differentialcost)*quantity*50;
				gain += price - quantity * sellers[selleraddresses[j]].differentialcost * 100;
				sum += price;
				price = 999 * price / 1000 - oraclefunds * 100;
				selleraddresses[j].transfer(price / 100);
				if (buyers[buyeraddresses[i]].amount == 0) {
					break;
				}
			}
			startprice -= buyers[buyeraddresses[i]].differentialcost * buyers[buyeraddresses[i]].amount;
			gain += startprice * 100 - sum;
			temp = 999 * (startprice * 100 - sum) / 1000 - oraclefunds * 100;
			buyeraddresses[i].transfer(temp / 100);
		}
		uint houseshare = 1000000000000000000 + gain / 1000; //the share of the deployer x100
		deployer.transfer(houseshare / 100);
		emit TransactionsCompleted();
		delete selleraddresses;
		delete buyeraddresses;
		indicb = 0;
		indics = 0;
	}

	function () external payable {} //needed for adding funds to the contract via web3.js
}
