const { expect } = require("chai");
const factoryABI = require("../artifacts/contracts/core/ACOFactory.sol/ACOFactory.json");

describe("ACOFactory", function() {
  let buidlerProxy;
  let buidlerFactory;
  let factoryInterface;
  let ACOFactory;
  let ACOToken;
  let owner;
  let addr1;
  let addr2;
  let fee = 100;
  let token1;
  let token1Name = "TOKEN1";
  let token1Symbol = "TOK1";
  let token1Decimals = 4;
  let token1TotalSupply = 9999990000;
  let token2;
  let token2Name = "TOKEN2";
  let token2Symbol = "TOK2";
  let token2Decimals = 8;
  let token2TotalSupply = 100000000000;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    
    ACOFactory = await (await ethers.getContractFactory("ACOFactory")).deploy();
    await ACOFactory.deployed();
    
    factoryInterface = new ethers.utils.Interface(factoryABI.abi);

    ACOToken = await (await ethers.getContractFactory("ACOToken")).deploy();
    await ACOToken.deployed();

    let ownerAddr = await owner.getAddress();
    let addr2Addr = await addr2.getAddress();
    let initData = factoryInterface.encodeFunctionData("init", [ownerAddr, ACOToken.address, fee, addr2Addr]);
    buidlerProxy = await (await ethers.getContractFactory("ACOProxy")).deploy(ownerAddr, ACOFactory.address, initData);
    await buidlerProxy.deployed();

    buidlerFactory = await ethers.getContractAt("ACOFactory", buidlerProxy.address);

    token1 = await (await ethers.getContractFactory("ERC20ForTest")).deploy(token1Name, token1Symbol, token1Decimals, token1TotalSupply);
    await token1.deployed();

    token2 = await (await ethers.getContractFactory("ERC20ForTest")).deploy(token2Name, token2Symbol, token2Decimals, token2TotalSupply);
    await token2.deployed();
  });
  
  describe("Proxy Deployment", function () {
    it("Should set the right proxy admin", async function () {
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
    });
    it("Should set the right proxy implementation", async function () {
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
    });
    it("Should set the right factory admin", async function () {
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
    });
    it("Should set the right factory fee", async function () {
      expect(await buidlerFactory.acoFee()).to.equal(fee);
    });
    it("Should set the right factory fee destination", async function () {
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
    });
    it("Should set the right factory ACO token", async function () {
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
    });
  });

  describe("Proxy transactions", function () {
    it("Check transfer proxy admin", async function () {
      await buidlerProxy.connect(owner).transferProxyAdmin(await addr1.getAddress());
      expect(await buidlerProxy.admin()).to.equal(await addr1.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);

      await buidlerProxy.connect(addr1).transferProxyAdmin(await addr2.getAddress());

      expect(await buidlerProxy.admin()).to.equal(await addr2.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
    });
    it("Check fail to transfer proxy admin", async function () {
      await expect(
        buidlerProxy.connect(owner).transferProxyAdmin(ethers.constants.AddressZero)
      ).to.be.revertedWith("ACOProxy::_setAdmin: Invalid admin");
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());

      await expect(
        buidlerProxy.connect(addr1).transferProxyAdmin(await addr1.getAddress())
      ).to.be.revertedWith("ACOProxy::onlyAdmin");
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
    });
    it("Check set proxy implementation", async function () {
      let newACOProxy = await (await ethers.getContractFactory("ACOFactoryForTest")).deploy();
      await newACOProxy.deployed();

      await buidlerProxy.connect(owner).setImplementation(newACOProxy.address, []);

      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(newACOProxy.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);

      await buidlerFactory.setAcoFee(fee * 2);
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(newACOProxy.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee * 2);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
 
      await expect(
        buidlerFactory.setAcoFee(30)
      ).to.be.revertedWith("ACOFactoryForTest::_setAcoFee: Invalid fee");
      expect(await buidlerFactory.acoFee()).to.equal(fee * 2);

      let newBuidlerFactory = await ethers.getContractAt("ACOFactoryForTest", buidlerProxy.address);
      await newBuidlerFactory.setExtraData(100);
      expect(await newBuidlerFactory.extraData()).to.equal(1);
      expect(await newBuidlerFactory.extraDataMap(1)).to.equal(100);
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(newACOProxy.address);
      expect(await newBuidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await newBuidlerFactory.acoFee()).to.equal(fee * 2);
      expect(await newBuidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await newBuidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);

      await newBuidlerFactory.setExtraData(500);
      expect(await newBuidlerFactory.extraData()).to.equal(2);
      expect(await newBuidlerFactory.extraDataMap(1)).to.equal(100);
      expect(await newBuidlerFactory.extraDataMap(2)).to.equal(500);
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(newACOProxy.address);
      expect(await newBuidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await newBuidlerFactory.acoFee()).to.equal(fee * 2);
      expect(await newBuidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await newBuidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);

      await newBuidlerFactory.setAcoFee(fee + 1);
      expect(await newBuidlerFactory.extraData()).to.equal(2);
      expect(await newBuidlerFactory.extraDataMap(1)).to.equal(100);
      expect(await newBuidlerFactory.extraDataMap(2)).to.equal(500);
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(newACOProxy.address);
      expect(await newBuidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await newBuidlerFactory.acoFee()).to.equal(fee + 1);
      expect(await newBuidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await newBuidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);

      let time = Math.round(new Date().getTime() / 1000) + 86400;
      let price = 3 * 10 ** token2Decimals;
      let tx = await (await newBuidlerFactory.connect(addr2).createAcoToken(token1.address, token2.address, false, price, time, 100)).wait();
      let result = tx.events[tx.events.length - 1].args;
      expect(result.underlying).to.equal(token1.address);
      expect(result.strikeAsset).to.equal(token2.address);
      expect(result.isCall).to.equal(false);
      expect(result.strikePrice).to.equal(price);
      expect(result.expiryTime).to.equal(time);
      expect(result.acoTokenImplementation).to.equal(ACOToken.address);
      
      await expect(
        newBuidlerFactory.connect(addr1).setExtraData(300)
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await newBuidlerFactory.extraData()).to.equal(2);

      await expect(
        newBuidlerFactory.connect(addr1).setFactoryAdmin(await addr1.getAddress())
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await newBuidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());

      await buidlerProxy.connect(owner).transferProxyAdmin(await addr1.getAddress());
      expect(await newBuidlerFactory.extraData()).to.equal(2);
      expect(await newBuidlerFactory.extraDataMap(1)).to.equal(100);
      expect(await newBuidlerFactory.extraDataMap(2)).to.equal(500);
      expect(await buidlerProxy.admin()).to.equal(await addr1.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(newACOProxy.address);
      expect(await newBuidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await newBuidlerFactory.acoFee()).to.equal(fee + 1);
      expect(await newBuidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await newBuidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
    });
    it("Check fail to set proxy implementation", async function () {
      let newACOProxy = await (await ethers.getContractFactory("ACOFactoryForTest")).deploy();
      await newACOProxy.deployed();

      await expect(
        buidlerProxy.connect(owner).setImplementation(ethers.constants.AddressZero, [])
      ).to.be.revertedWith("ACOProxy::_setImplementation: Invalid implementation");
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);

      await expect(
        buidlerProxy.connect(addr1).setImplementation(newACOProxy.address, [])
      ).to.be.revertedWith("ACOProxy::onlyAdmin");
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
    });
  });

  describe("ACOFactory transactions", function () {
    it("Check set factory admin", async function () {
      await buidlerFactory.setFactoryAdmin(await addr1.getAddress());
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await addr1.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
    });
    it("Check fail to set factory admin", async function () {
      await expect(
        buidlerFactory.connect(owner).setFactoryAdmin(ethers.constants.AddressZero)
      ).to.be.revertedWith("ACOFactory::_setFactoryAdmin: Invalid factory admin");
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());

      await expect(
        buidlerFactory.connect(addr1).setFactoryAdmin(await addr1.getAddress())
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
    });
    it("Check set ACO token implementation", async function () {
      let newACOToken = await (await ethers.getContractFactory("ACOToken")).deploy();
      await newACOToken.deployed();

      await buidlerFactory.setAcoTokenImplementation(newACOToken.address);
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(newACOToken.address);
    });
    it("Check fail to set ACO token implementation", async function () {
      await expect(
        buidlerFactory.connect(owner).setAcoTokenImplementation(ethers.constants.AddressZero)
      ).to.be.revertedWith("ACOFactory::_setAcoTokenImplementation: Invalid ACO token implementation");
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);

      await expect(
        buidlerFactory.connect(addr1).setAcoTokenImplementation(ACOToken.address)
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
    });
    it("Check set ACO fee", async function () {
      await buidlerFactory.setAcoFee(fee * 2);
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee * 2);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
    });
    it("Check fail to set ACO fee", async function () {
      await expect(
        buidlerFactory.connect(addr1).setAcoFee(fee * 2)
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await buidlerFactory.acoFee()).to.equal(fee);
    });
    it("Check set ACO fee destination", async function () {
      await buidlerFactory.setAcoFeeDestination(await owner.getAddress());
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(ACOToken.address);
    });
    it("Check fail to set ACO fee destination", async function () {
      await expect(
        buidlerFactory.connect(owner).setAcoFeeDestination(ethers.constants.AddressZero)
      ).to.be.revertedWith("ACOFactory::_setAcoFeeDestination: Invalid ACO fee destination");
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());

      await expect(
        buidlerFactory.connect(addr1).setAcoFeeDestination(await owner.getAddress())
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
    });
    it("Set operator", async function () {
      expect(await buidlerFactory.operators(await owner.getAddress())).to.equal(true);
      expect(await buidlerFactory.operators(await addr1.getAddress())).to.equal(false);
      expect(await buidlerFactory.operators(await addr2.getAddress())).to.equal(false);

      await expect(
        buidlerFactory.connect(addr1).setOperator(await addr1.getAddress(), true)
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");

      expect(await buidlerFactory.operators(await owner.getAddress())).to.equal(true);
      expect(await buidlerFactory.operators(await addr1.getAddress())).to.equal(false);
      expect(await buidlerFactory.operators(await addr2.getAddress())).to.equal(false);

      await buidlerFactory.setOperator(await addr1.getAddress(), true);

      expect(await buidlerFactory.operators(await owner.getAddress())).to.equal(true);
      expect(await buidlerFactory.operators(await addr1.getAddress())).to.equal(true);
      expect(await buidlerFactory.operators(await addr2.getAddress())).to.equal(false);

      await buidlerFactory.setOperator(await addr2.getAddress(), true);

      expect(await buidlerFactory.operators(await owner.getAddress())).to.equal(true);
      expect(await buidlerFactory.operators(await addr1.getAddress())).to.equal(true);
      expect(await buidlerFactory.operators(await addr2.getAddress())).to.equal(true);

      await buidlerFactory.setOperator(await addr1.getAddress(), false);

      expect(await buidlerFactory.operators(await owner.getAddress())).to.equal(true);
      expect(await buidlerFactory.operators(await addr1.getAddress())).to.equal(false);
      expect(await buidlerFactory.operators(await addr2.getAddress())).to.equal(true);
    });
    it("Check fail to set operator", async function () {
      await expect(
        buidlerFactory.connect(addr1).setOperator(await addr1.getAddress(), true)
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await buidlerFactory.operators(await addr1.getAddress())).to.equal(false);
    });
    it("Check ACO token admin creation", async function () {
      const maxExercisedAccounts = 120;
      let time = Math.round(new Date().getTime() / 1000) + 86400;
      let price = 2 * 10 ** token2Decimals;
      let tx = await (await buidlerFactory.createAcoToken(ethers.constants.AddressZero, token2.address, true, price, time, maxExercisedAccounts)).wait();
      let result1 = tx.events[tx.events.length - 1].args;
      expect(result1.underlying).to.equal(ethers.constants.AddressZero);
      expect(result1.strikeAsset).to.equal(token2.address);
      expect(result1.isCall).to.equal(true);
      expect(result1.strikePrice).to.equal(price);
      expect(result1.expiryTime).to.equal(time);
      expect(result1.acoTokenImplementation).to.equal(ACOToken.address);
      let aco1 = result1.acoToken;
      data = await buidlerFactory.acoTokenData(aco1);
      expect(data[0]).to.equal(ethers.constants.AddressZero);
      expect(data[1]).to.equal(token2.address);
      expect(data[2]).to.equal(true);
      expect(data[3]).to.equal(price);
      expect(data[4]).to.equal(time);

      buidlerToken = await ethers.getContractAt("ACOToken", aco1);     
      expect(await buidlerToken.underlying()).to.equal(ethers.constants.AddressZero);    
      expect(await buidlerToken.strikeAsset()).to.equal(token2.address);    
      expect(await buidlerToken.isCall()).to.equal(true); 
      expect(await buidlerToken.strikePrice()).to.equal(price); 
      expect(await buidlerToken.expiryTime()).to.equal(time); 
      expect(await buidlerToken.acoFee()).to.equal(fee); 
      expect(await buidlerToken.feeDestination()).to.equal(await addr2.getAddress()); 
      expect(await buidlerToken.totalCollateral()).to.equal(0); 
      expect(await buidlerToken.underlyingSymbol()).to.equal("ETH");
      expect(await buidlerToken.underlyingDecimals()).to.equal(18);
      expect(await buidlerToken.strikeAssetSymbol()).to.equal(token2Symbol);
      expect(await buidlerToken.strikeAssetDecimals()).to.equal(token2Decimals);
      expect(await buidlerToken.maxExercisedAccounts()).to.equal(maxExercisedAccounts);

      let newACOToken2 = await (await ethers.getContractFactory("ACOToken")).deploy();
      await newACOToken2.deployed();
      await buidlerFactory.setAcoTokenImplementation(newACOToken2.address);
      tx = await (await buidlerFactory.createAcoToken(token1.address, token2.address, false, price, time, maxExercisedAccounts)).wait();
      let result2 = tx.events[tx.events.length - 1].args;
      expect(result2.underlying).to.equal(token1.address);
      expect(result2.strikeAsset).to.equal(token2.address);
      expect(result2.isCall).to.equal(false);
      expect(result2.strikePrice).to.equal(price);
      expect(result2.expiryTime).to.equal(time);
      expect(result2.acoTokenImplementation).to.equal(newACOToken2.address);
      let aco2 = result2.acoToken;
      data = await buidlerFactory.acoTokenData(aco2);
      expect(data[0]).to.equal(token1.address);
      expect(data[1]).to.equal(token2.address);
      expect(data[2]).to.equal(false);
      expect(data[3]).to.equal(price);
      expect(data[4]).to.equal(time);

      buidlerToken = await ethers.getContractAt("ACOToken", aco2);     
      expect(await buidlerToken.underlying()).to.equal(token1.address);    
      expect(await buidlerToken.strikeAsset()).to.equal(token2.address);    
      expect(await buidlerToken.isCall()).to.equal(false); 
      expect(await buidlerToken.strikePrice()).to.equal(price); 
      expect(await buidlerToken.expiryTime()).to.equal(time); 
      expect(await buidlerToken.acoFee()).to.equal(fee); 
      expect(await buidlerToken.feeDestination()).to.equal(await addr2.getAddress()); 
      expect(await buidlerToken.totalCollateral()).to.equal(0); 
      expect(await buidlerToken.underlyingSymbol()).to.equal(token1Symbol);
      expect(await buidlerToken.underlyingDecimals()).to.equal(token1Decimals);
      expect(await buidlerToken.strikeAssetSymbol()).to.equal(token2Symbol);
      expect(await buidlerToken.strikeAssetDecimals()).to.equal(token2Decimals);
      expect(await buidlerToken.maxExercisedAccounts()).to.equal(maxExercisedAccounts);

      await expect(
        buidlerToken.init(token1.address, token2.address, false, price, time, fee, await addr2.getAddress(), maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::init: Already initialized");
      
      expect(await buidlerProxy.admin()).to.equal(await owner.getAddress());
      expect(await buidlerProxy.implementation()).to.equal(ACOFactory.address);
      expect(await buidlerFactory.factoryAdmin()).to.equal(await owner.getAddress());
      expect(await buidlerFactory.acoFee()).to.equal(fee);
      expect(await buidlerFactory.acoFeeDestination()).to.equal(await addr2.getAddress());
      expect(await buidlerFactory.acoTokenImplementation()).to.equal(newACOToken2.address);

      data = await buidlerFactory.acoTokenData(result1.acoToken);
      expect(data[0]).to.equal(ethers.constants.AddressZero);
      expect(data[1]).to.equal(token2.address);
      expect(data[2]).to.equal(true);
      expect(data[3]).to.equal(price);
      expect(data[4]).to.equal(time);
      data = await buidlerFactory.acoTokenData(result2.acoToken);
      expect(data[0]).to.equal(token1.address);
      expect(data[1]).to.equal(token2.address);
      expect(data[2]).to.equal(false);
      expect(data[3]).to.equal(price);
      expect(data[4]).to.equal(time);
    });
    it("Check fail to ACO token admin creation", async function () {
      const maxExercisedAccounts = 120;
      let time = Math.round(new Date().getTime() / 1000) + 86400;
      let price = 3 * 10 ** token2Decimals;

      await buidlerFactory.setOperator(await owner.getAddress(), false);

      await expect(
        buidlerFactory.createAcoToken(token1.address, token2.address, false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOFactory::createAcoToken: Only authorized operators");

      await buidlerFactory.setOperator(await owner.getAddress(), true);
      
      await expect(
        buidlerFactory.createAcoToken(token1.address, token2.address, false, price, 0, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::init: Invalid expiry");
      await expect(
        buidlerFactory.createAcoToken(token1.address, token2.address, false, 0, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::init: Invalid strike price");
      await expect(
        buidlerFactory.createAcoToken(token1.address, token1.address, false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::init: Same assets");
      await expect(
        buidlerFactory.createAcoToken(await owner.getAddress(), token2.address, false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::init: Invalid underlying");
      await expect(
        buidlerFactory.createAcoToken(token2.address, await owner.getAddress(), false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::init: Invalid strike asset");
      await expect(
        buidlerFactory.createAcoToken(token1.address, ACOFactory.address, false, price, time, 1)
      ).to.be.revertedWith("ACOToken::init: Invalid number to max exercised accounts");
      await expect(
        buidlerFactory.createAcoToken(token1.address, ACOFactory.address, false, price, time, 200)
      ).to.be.revertedWith("ACOToken::init: Invalid number to max exercised accounts");
      await expect(
        buidlerFactory.createAcoToken(ACOFactory.address, token1.address, false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::_getAssetDecimals: Invalid asset decimals");
      await expect(
        buidlerFactory.createAcoToken(token1.address, ACOFactory.address, false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::_getAssetDecimals: Invalid asset decimals");

      await buidlerFactory.setAcoFee(501);
      expect(await buidlerFactory.acoFee()).to.equal(501);
      await expect(
        buidlerFactory.createAcoToken(token1.address, token2.address, false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOToken::init: Invalid ACO fee");   

      await buidlerFactory.setAcoFee(100);
      await buidlerFactory.createAcoToken(token1.address, token2.address, false, price, time, maxExercisedAccounts);
      await expect(
        buidlerFactory.createAcoToken(token1.address, token2.address, false, price, time, maxExercisedAccounts)
      ).to.be.revertedWith("ACOFactory::_createAcoToken: ACO already exists");

      await expect(
        buidlerFactory.createAcoToken(token1.address, token2.address, true, price, time + 200000000, maxExercisedAccounts)
      ).to.be.revertedWith("ACOFactory::_createAcoToken: Invalid expiry time");
    });
    it("Check set ACO strike asset permitted", async function () {
      expect(await buidlerFactory.strikeAssets(token1.address)).to.equal(false);  
      expect(await buidlerFactory.strikeAssets(token2.address)).to.equal(false); 
      await buidlerFactory.setStrikeAssetPermission(token2.address, true);
      await buidlerFactory.setStrikeAssetPermission(token1.address, true);
      expect(await buidlerFactory.strikeAssets(token1.address)).to.equal(true); 
      expect(await buidlerFactory.strikeAssets(token2.address)).to.equal(true); 
      
      await buidlerFactory.setStrikeAssetPermission(token1.address, false);
      expect(await buidlerFactory.strikeAssets(token1.address)).to.equal(false); 
      expect(await buidlerFactory.strikeAssets(token2.address)).to.equal(true); 
    });
    it("Check fail to set ACO strike asset permitted", async function () {
      await expect(
        buidlerFactory.connect(addr1).setStrikeAssetPermission(token1.address, true)
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect(await buidlerFactory.strikeAssets(token1.address)).to.equal(false); 
    });
    it("Check set asset specific data", async function () {
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxSignificantDigits).to.equal(0); 
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxExercisedAccounts).to.equal(0); 
      expect((await buidlerFactory.assetsSpecificData(token2.address)).maxSignificantDigits).to.equal(0); 
      expect((await buidlerFactory.assetsSpecificData(token2.address)).maxExercisedAccounts).to.equal(0);  
      expect(await buidlerFactory.setAssetSpecificData(token1.address, 5, 90)); 
      expect(await buidlerFactory.setAssetSpecificData(token2.address, 4, 0)); 
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxSignificantDigits).to.equal(5); 
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxExercisedAccounts).to.equal(90); 
      expect((await buidlerFactory.assetsSpecificData(token2.address)).maxSignificantDigits).to.equal(4); 
      expect((await buidlerFactory.assetsSpecificData(token2.address)).maxExercisedAccounts).to.equal(0);  
      
      expect(await buidlerFactory.setAssetSpecificData(token1.address, 0, 90)); 
      expect(await buidlerFactory.setAssetSpecificData(token2.address, 0, 0)); 
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxSignificantDigits).to.equal(0); 
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxExercisedAccounts).to.equal(90); 
      expect((await buidlerFactory.assetsSpecificData(token2.address)).maxSignificantDigits).to.equal(0); 
      expect((await buidlerFactory.assetsSpecificData(token2.address)).maxExercisedAccounts).to.equal(0);  
    });
    it("Check fail to set asset specific data", async function () {
      await expect(
        buidlerFactory.connect(addr1).setAssetSpecificData(token1.address, 5, 90)
      ).to.be.revertedWith("ACOFactory::onlyFactoryAdmin");
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxSignificantDigits).to.equal(0); 
      expect((await buidlerFactory.assetsSpecificData(token1.address)).maxExercisedAccounts).to.equal(0);  
    });
    it("Check ACO token open creation", async function () {
      await buidlerFactory.setStrikeAssetPermission(token2.address, true);

      const maxExercisedAccounts = 100;
      let now = new Date();
      now.setMonth(now.getMonth()+1);
      let time = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate(), 8, 0, 0, 0)/1000;
      
      let price = 3 * 10 ** token2Decimals;
      let tx = await (await buidlerFactory.connect(addr2).newAcoToken(token1.address, token2.address, false, price, time)).wait();
      let result = tx.events[tx.events.length - 1].args;
      expect(result.underlying).to.equal(token1.address);
      expect(result.strikeAsset).to.equal(token2.address);
      expect(result.isCall).to.equal(false);
      expect(result.strikePrice).to.equal(price);
      expect(result.expiryTime).to.equal(time);
      expect(result.acoTokenImplementation).to.equal(ACOToken.address);

      let buidlerToken = await ethers.getContractAt("ACOToken", result.acoToken);     
      expect(await buidlerToken.underlying()).to.equal(token1.address);    
      expect(await buidlerToken.strikeAsset()).to.equal(token2.address);    
      expect(await buidlerToken.isCall()).to.equal(false); 
      expect(await buidlerToken.strikePrice()).to.equal(price); 
      expect(await buidlerToken.expiryTime()).to.equal(time); 
      expect(await buidlerToken.acoFee()).to.equal(fee); 
      expect(await buidlerToken.feeDestination()).to.equal(await addr2.getAddress()); 
      expect(await buidlerToken.totalCollateral()).to.equal(0); 
      expect(await buidlerToken.underlyingSymbol()).to.equal(token1Symbol);
      expect(await buidlerToken.underlyingDecimals()).to.equal(token1Decimals);
      expect(await buidlerToken.strikeAssetSymbol()).to.equal(token2Symbol);
      expect(await buidlerToken.strikeAssetDecimals()).to.equal(token2Decimals);
      expect(await buidlerToken.maxExercisedAccounts()).to.equal(maxExercisedAccounts);
      expect(await buidlerFactory.getAcoToken(token1.address, token2.address, false, price, time)).to.equal(result.acoToken);
      
      expect(await buidlerFactory.setAssetSpecificData(token1.address, 0, 90)); 
      expect(await buidlerFactory.setAssetSpecificData(token2.address, 0, 80)); 
    
      tx = await (await buidlerFactory.connect(addr2).newAcoToken(token1.address, token2.address, true, price, time)).wait();
      result = tx.events[tx.events.length - 1].args;
      expect(result.underlying).to.equal(token1.address);
      expect(result.strikeAsset).to.equal(token2.address);
      expect(result.isCall).to.equal(true);
      expect(result.strikePrice).to.equal(price);
      expect(result.expiryTime).to.equal(time);
      expect(result.acoTokenImplementation).to.equal(ACOToken.address);

      buidlerToken = await ethers.getContractAt("ACOToken", result.acoToken);     
      expect(await buidlerToken.underlying()).to.equal(token1.address);    
      expect(await buidlerToken.strikeAsset()).to.equal(token2.address);    
      expect(await buidlerToken.isCall()).to.equal(true); 
      expect(await buidlerToken.strikePrice()).to.equal(price); 
      expect(await buidlerToken.expiryTime()).to.equal(time); 
      expect(await buidlerToken.acoFee()).to.equal(fee); 
      expect(await buidlerToken.feeDestination()).to.equal(await addr2.getAddress()); 
      expect(await buidlerToken.totalCollateral()).to.equal(0); 
      expect(await buidlerToken.underlyingSymbol()).to.equal(token1Symbol);
      expect(await buidlerToken.underlyingDecimals()).to.equal(token1Decimals);
      expect(await buidlerToken.strikeAssetSymbol()).to.equal(token2Symbol);
      expect(await buidlerToken.strikeAssetDecimals()).to.equal(token2Decimals);
      expect(await buidlerToken.maxExercisedAccounts()).to.equal(90);
      expect(await buidlerFactory.getAcoToken(token1.address, token2.address, true, price, time)).to.equal(result.acoToken);

      tx = await (await buidlerFactory.connect(addr2).newAcoToken(token1.address, token2.address, false, price * 1.01, time)).wait();
      result = tx.events[tx.events.length - 1].args;
      expect(result.underlying).to.equal(token1.address);
      expect(result.strikeAsset).to.equal(token2.address);
      expect(result.isCall).to.equal(false);
      expect(result.strikePrice).to.equal(price * 1.01);
      expect(result.expiryTime).to.equal(time);
      expect(result.acoTokenImplementation).to.equal(ACOToken.address);

      buidlerToken = await ethers.getContractAt("ACOToken", result.acoToken);     
      expect(await buidlerToken.underlying()).to.equal(token1.address);    
      expect(await buidlerToken.strikeAsset()).to.equal(token2.address);    
      expect(await buidlerToken.isCall()).to.equal(false); 
      expect(await buidlerToken.strikePrice()).to.equal(price * 1.01); 
      expect(await buidlerToken.expiryTime()).to.equal(time); 
      expect(await buidlerToken.acoFee()).to.equal(fee); 
      expect(await buidlerToken.feeDestination()).to.equal(await addr2.getAddress()); 
      expect(await buidlerToken.totalCollateral()).to.equal(0); 
      expect(await buidlerToken.underlyingSymbol()).to.equal(token1Symbol);
      expect(await buidlerToken.underlyingDecimals()).to.equal(token1Decimals);
      expect(await buidlerToken.strikeAssetSymbol()).to.equal(token2Symbol);
      expect(await buidlerToken.strikeAssetDecimals()).to.equal(token2Decimals);
      expect(await buidlerToken.maxExercisedAccounts()).to.equal(80);
      expect(await buidlerFactory.getAcoToken(token1.address, token2.address, false, price * 1.01, time)).to.equal(result.acoToken);
    });
    it("Check fail to ACO token open creation", async function () {
      let now = new Date();
      now.setMonth(now.getMonth()+1);
      let time = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate(), 8, 0, 0, 0)/1000;
      let price = 3 * 10 ** token2Decimals;

      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, false, price, time)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid strike asset");
      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, true, price, time)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid strike asset");
      
      await buidlerFactory.setStrikeAssetPermission(token2.address, true);

      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, false, price, time+1)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid expiry time");
      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, true, price, time+1)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid expiry time");
      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, false, price, time+43200)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid expiry time");
      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, true, price, time+43200)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid expiry time");

      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, false, Math.round(price * 1.001), time)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid strike price");
      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, true, Math.round(price * 1.001), time)
      ).to.be.revertedWith("ACOFactory::newAcoToken: Invalid strike price");

      await buidlerFactory.setAssetSpecificData(token2.address, 4, 0);
      await buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, false, Math.round(price * 1.001), time);
      await buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, true, Math.round(price * 1.001), time);

      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, false, Math.round(price * 1.001), time)
      ).to.be.revertedWith("ACOFactory::_createAcoToken: ACO already exists");
      await expect(
        buidlerFactory.connect(addr1).newAcoToken(token1.address, token2.address, true, Math.round(price * 1.001), time)
      ).to.be.revertedWith("ACOFactory::_createAcoToken: ACO already exists");

      await expect(
        buidlerFactory.newAcoToken(token1.address, token2.address, true, price, time + 158025600)
      ).to.be.revertedWith("ACOFactory::_createAcoToken: Invalid expiry time");
      await expect(
        buidlerFactory.newAcoToken(token1.address, token2.address, false, price, time + 158025600)
      ).to.be.revertedWith("ACOFactory::_createAcoToken: Invalid expiry time");
    });
  });
});