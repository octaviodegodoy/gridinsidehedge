//+------------------------------------------------------------------+
//|                                                TheGridInside.mq4 |
//|                        Copyright 2015, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2015, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#include <stdlib.mqh>
#include <stderror.mqh>


int digits;
double lotSize;
double minLot;
double myPoint;
double accountEquity;
double leverage;
int slippage=2;
int magicNumber=23453243;

extern double loadPercent=0.20; // Percentage of Equity
extern bool useMM=true;
extern double fixedLot=0.01;
double initialLot;
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
enum tradeCriteria
  {
   a=1,// Fibo Levels
   b=2     // Donchian Channels
  };

// TradeCriteria
input tradeCriteria tradeCriteriaType=a;      // Trade Criteria
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
enum closeCriteria
  {
   c=1,// Average Price
   d=2     // Money Target
  };
// Close criteria
input closeCriteria closeCriteriaType=c;      // Close Criteria

extern double moneyTarget=25.00;
extern double risk=1;
extern double depositLoad=2000;

// Margin Parameters

extern double marginLevelLimit=10000;

// Hedge Parameters

bool lockMode=false;

double hedgeBuyPriceTarget=9999;
double hedgeSellPriceTarget=-9999;
double lastHedgeBuyTarget=9999;
double lastHedgeSellTarget=-9999;
bool hedgeMode=false;
int totalHedgeOrders=0;
double HedgeSellLevel=0;
double HedgeBuyLevel=0;


// Order accounting 
int totalOrders;
int totalBuyOrders;
int totalSellOrders;
double sumSellLots;
double sumBuyLots;
double usdTickPriceSell;
double usdTickPriceBuy;
double availableTicksSell;
double availableTicksBuy;
double averagePriceSell;
double averagePriceBuy;
double sellWeightedAverage;
double buyWeightedAverage;
double stopOutLevel;

double priceLimitSell;
double priceStopOutSell;
double priceLimitBuy;
double priceStopOutBuy;
int highestCandleShift;
int lowestCandleShift;
double highestCandlePrice;
double lowestCandlePrice;
double middleCandlePrice;

//+------------------------------------------------------------------+
//| ATR DATA                                  |
//+------------------------------------------------------------------+

double currentATRPoints;

//+------------------------------------------------------------------+
//| FIBO DATA                                  |
//+------------------------------------------------------------------+
double fiboPriceLevel1;
double fiboPriceLevel2;
double fiboPriceLevel3;
double fiboPriceLevel4;
double fiboPriceLevel5;
double fiboPriceLevel6;
double fiboPriceLevel7;
double fiboBuyPriceTarget=9999;
double fiboSellPriceTarget=-9999;
double lastFiboBuyTarget=9999;
double lastFiboSellTarget=-9999;
double lastCCI=9999;

extern double takeProfit= 20;
extern bool displayInfo = true;
extern bool displayObjects=true;
extern bool buyAndSell=true; // Buy and Sell simultaneously
extern double lotFactor=1.1;
extern int maxOrders=50;
extern double minGridSpace=30.0;
extern double pipStep=20;
extern int targetThreshold=3;

// ATR DATA

extern double MaxATR=600;
extern int atrPeriod=2;

//
// Market Hours
//

extern string initHour= "00:00"; // Trade init time GMT
extern string endHour = "23:59"; // Trade end time GMT

input bool Monday    = true; // Monday GMT
input bool Tuesday   = true; // Tuesday GMT
input bool Wednesday = true; // Wednesday GMT
input bool Thursday  = true; // Thursday GMT
input bool Friday    = true; // Friday GMT



double initialEquity= 0;
double currentEquity=0;
double sumBuyPrices;
double sumSellPrices;

int countCloseLoss=0;
int countCloseProfit=0;
double ordersProfitLossFactor=0;
double emergencySellProfit= 0;
double emergencyBuyProfit = 0;
double buyDrawdown=0;
double sellDrawdown=0;

int errorMessage=0;
bool waitNextError=false;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {

   digits=(int) MarketInfo(NULL,MODE_DIGITS);
   lotSize= MarketInfo(NULL,MODE_LOTSIZE);
   minLot = MarketInfo(NULL,MODE_MINLOT);
   myPoint= MarketInfo(NULL,MODE_POINT);
   leverage=AccountLeverage();
   stopOutLevel=AccountStopoutLevel();

   sumBuyPrices=NormalizeDouble(0,digits);
   sumSellPrices=NormalizeDouble(0,digits);

   SystemAccounting();

//--- create timer
   EventSetTimer(1);

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

   if(IsTesting()) return;
   string PN="TGI";
   for(int i=ObjectsTotal()-1; i>=0; i--)
     {
      string Obj_Name=ObjectName(i);
      if(StringFind(Obj_Name,PN,0)!=-1)
        {
         ObjectDelete(Obj_Name);
        }
     }
   Comment("");
   return;
//--- destroy timer
   EventKillTimer();

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

 
   TradeCriteria();

   if(displayInfo)
     {
      DisplayInfo();
     }

   if(displayObjects)
     {

      DisplayObjects();

     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CountBuyLots()
  {

   double orderBuyLotCount=0;
   for(int i=0;i<totalOrders;i++)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
        {
         Print("Error selecting orders CountBuyLots ",GetLastError());
        }

      if(OrderSymbol()!=Symbol()) continue;
      if(OrderType()==OP_BUY)
        {

         orderBuyLotCount+=OrderLots();

        }

     }

   return orderBuyLotCount;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsTradingTime()
  {

   datetime dateHourInit= StrToTime(initHour);
   datetime dateHourEnd = StrToTime(endHour);
   datetime hourGMT=TimeGMT();

   int weekDayGMT=TimeDayOfWeek(hourGMT);

   MqlDateTime hourGMTStruct;
   MqlDateTime hourInitStruct;
   MqlDateTime hourEndStruct;

   TimeToStruct(hourGMT,hourGMTStruct);
   TimeToStruct(dateHourInit,hourInitStruct);
   TimeToStruct(dateHourEnd,hourEndStruct);

//TODO comparar cada dia da semana com o dia da semana atual e associar ao GMT.

   bool compareTradeHours=((hourGMTStruct.hour>hourInitStruct.hour) && (hourGMTStruct.hour<hourEndStruct.hour))
                          ||((hourGMTStruct.hour == hourInitStruct.hour)&&(hourGMTStruct.min >= hourInitStruct.min))
                          ||((hourGMTStruct.hour == hourEndStruct.hour)&&(hourGMTStruct.min <= hourEndStruct.min));

   bool weekDayTrade=((weekDayGMT==1) && Monday)
                     || ((weekDayGMT == 2) && Tuesday )
                     || ((weekDayGMT == 3) && Wednesday )
                     || ((weekDayGMT == 4) && Thursday )
                     || ((weekDayGMT == 5) && Friday );



   bool tradeHour=compareTradeHours && weekDayTrade;

   return tradeHour;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double LotOptimizing()
  {

   double equity=AccountEquity();

   double lotsize=MarketInfo(NULL,MODE_LOTSIZE);

   double depoLoad=equity*loadPercent;

   int lev=AccountLeverage();

   double lotEquity=NormalizeDouble(depoLoad/lotsize,2);

   return lotEquity;

  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
//---

  }
//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester()
  {
//---
   double ret=0.0;
//---

//---
   return(ret);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SystemAccounting()
  {

// Orders account
   totalOrders=OrdersTotal();
   totalBuyOrders=0;
   totalSellOrders=0;
   sumBuyPrices=0;
   sumSellPrices=0;
   sumBuyLots=0;
   sumSellLots=0;
   averagePriceBuy=0;
   averagePriceSell=0;
   priceLimitSell=0;
   priceStopOutSell=0;
   priceStopOutBuy=0;
   priceLimitBuy=0;

// Reset Hedge Mode
   if(totalOrders==0)
     {

      hedgeMode=false;
      lockMode=false;

     }

   for(int i=0;i<totalOrders;i++)
     {

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderSymbol()!=Symbol()) continue;

         if(OrderType()==OP_BUY)
           {
            totalBuyOrders++;
            sumBuyPrices+=OrderOpenPrice();
            sumBuyLots+=OrderLots();

           }

         if(OrderType()==OP_SELL)
           {
            totalSellOrders++;
            sumSellPrices+=OrderOpenPrice();
            sumSellLots+=OrderLots();
           }

        }
      else
        {
         Print(" Error selecting order accounting ",GetLastError());
        }
     } // for select

// next buy position

   UpdateFiboLevels();

// Drawdown Control
   double profitsBuy=GetProfitBuys();
   double profitsSell=GetProfitSells();

   buyDrawdown=profitsBuy/(depositLoad*risk);

   sellDrawdown=profitsSell/(depositLoad*risk);

   sumBuyPrices=NormalizeDouble(sumBuyPrices,digits);
   sumSellPrices=NormalizeDouble(sumSellPrices,digits);

   if(totalBuyOrders>0)
     {
      averagePriceBuy = sumBuyPrices/totalBuyOrders;
      averagePriceBuy = NormalizeDouble(averagePriceBuy,digits);

     }

   if(totalSellOrders>0)
     {

      averagePriceSell = sumSellPrices/totalSellOrders;
      averagePriceSell = NormalizeDouble(averagePriceSell,digits);

     }

// Money account

   currentEquity=AccountEquity();

   usdTickPriceSell=NormalizeDouble(MarketInfo(NULL,MODE_TICKVALUE)*sumSellLots,2);

   usdTickPriceBuy=NormalizeDouble(MarketInfo(NULL,MODE_TICKVALUE)*sumBuyLots,2);

   if(usdTickPriceSell>=0.01)
     {
      availableTicksSell=NormalizeDouble(currentEquity/usdTickPriceSell,1);
     }

   if(usdTickPriceBuy>=0.01)
     {

      availableTicksBuy=NormalizeDouble(currentEquity/usdTickPriceBuy,1);

     }

   priceLimitSell=NormalizeDouble(averagePriceSell+availableTicksSell*myPoint,digits);
   priceStopOutSell=NormalizeDouble(averagePriceSell+availableTicksSell*(1-stopOutLevel/100)*myPoint,digits);
   priceLimitBuy=NormalizeDouble(averagePriceBuy-availableTicksBuy*myPoint,digits);
   priceStopOutBuy=NormalizeDouble(averagePriceBuy-availableTicksBuy*(1-stopOutLevel/100)*myPoint,digits);

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DisplayObjects()
  {

   sellWeightedAverage=GetSellWeightedAverage();
   TEXT("TGI_WEIGHTED_TEXT",sellWeightedAverage,"SELL WEIGHTED AVG",15,clrRed);
   HORIZONTAL_LINE("TGI_WEIGHTED_SELL",sellWeightedAverage,STYLE_DASHDOT,5,clrRed);

   HORIZONTAL_LINE("TGI_FIBO_LEVEL2",fiboPriceLevel2,STYLE_SOLID,1,clrAntiqueWhite);
   HORIZONTAL_LINE("TGI_FIBO_BUY_TARGET",fiboBuyPriceTarget,STYLE_SOLID,1,clrChartreuse);

   HORIZONTAL_LINE("TGI_FIBO_LEVEL6",fiboPriceLevel6,STYLE_SOLID,1,clrCornsilk);
   TEXT("TGI_TXT_SELL_TARGET",fiboSellPriceTarget,"SELL TARGET",10,clrOrange);
   HORIZONTAL_LINE("TGI_FIBO_SELL_TARGET",fiboSellPriceTarget,STYLE_SOLID,1,clrOrange);
  
   buyWeightedAverage=GetBuyWeightedAverage();

   HORIZONTAL_LINE("TGI_WEIGHTED_AVG_PRICE_BUY",buyWeightedAverage,STYLE_DASH,5,clrBlue);
   TEXT("TGI_BUY_WEIGHTED_AVG_TEXT",buyWeightedAverage,"BUY WEIGHTED AVG",15,clrBlue);

   HORIZONTAL_LINE("TGI_SELL_LIMIT_LEVEL",priceLimitSell,STYLE_SOLID,1,clrBlueViolet);
   HORIZONTAL_LINE("TGI_BUY_LIMIT_LEVEL",priceLimitBuy,STYLE_SOLID,1,clrBlueViolet);
   
   
   HORIZONTAL_LINE("TGI_HEDGE_SELL_LEVEL",HedgeSellLevel,STYLE_SOLID,1,clrBlueViolet);
   HORIZONTAL_LINE("TGI_HEDGE_BUY_LEVEL",HedgeBuyLevel,STYLE_SOLID,1,clrBlueViolet);


   if(AccountStopoutMode()==0)
     {

      HORIZONTAL_LINE("TGI_SELL_STOPOUT_LEVEL",priceStopOutSell,STYLE_SOLID,1,clrRed);
      HORIZONTAL_LINE("TGI_BUY_STOPOUT_LEVEL",priceStopOutBuy,STYLE_SOLID,1,clrRed);

     }

/*
   HORIZONTAL_LINE("TGI_FIBO_LEVEL0",lowestCandlePrice,STYLE_SOLID,clrAntiqueWhite);
   HORIZONTAL_LINE("TGI_FIBO_LEVEL1",fiboPriceLevel1,STYLE_SOLID,clrAntiqueWhite);
   HORIZONTAL_LINE("TGI_FIBO_LEVEL2",fiboPriceLevel2,STYLE_SOLID,clrAntiqueWhite);
   HORIZONTAL_LINE("TGI_FIBO_LEVEL3",fiboPriceLevel3,STYLE_SOLID,clrAntiqueWhite);
   HORIZONTAL_LINE("TGI_FIBO_LEVEL4",fiboPriceLevel4,STYLE_SOLID,clrAntiqueWhite);
   HORIZONTAL_LINE("TGI_FIBO_LEVEL5",fiboPriceLevel5,STYLE_SOLID,clrAntiqueWhite);
   HORIZONTAL_LINE("TGI_FIBO_LEVEL6",fiboPriceLevel6,STYLE_SOLID,clrAntiqueWhite);
   
   HORIZONTAL_LINE("TGI_FIBO_BUY_PRICE",fiboBuyPriceTarget,STYLE_SOLID,clrOrange);
   HORIZONTAL_LINE("TGI_FIBO_SELL_PRICE",fiboSellPriceTarget,STYLE_SOLID,clrAqua);
   
   */

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TradeCriteria()
  {

// Choosing the trading criteria
   switch(tradeCriteriaType)
     {

      case 1 : FiboLevels();
      break;

     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetBuyWeightedAverage()
  {
   int total=OrdersTotal();
   double sumWeightedAverage=0;
   double sumLotsBuy=0;
   double result=0;
   for(int i=0;i<total;i++)
     {
      if(OrderSelect(i,SELECT_BY_POS))
        {
         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_BUY)
           {

            sumWeightedAverage+=OrderOpenPrice()*OrderLots();
            sumLotsBuy+=OrderLots();

           }

        }

     }

   if(sumLotsBuy>0)
     {
      result=NormalizeDouble(sumWeightedAverage/sumLotsBuy,digits);
     }

   return result;


  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetSellWeightedAverage()
  {
   int total=OrdersTotal();
   double sumWeightedAverage=0;
   double sumLotsSell=0;
   double result=0;
   for(int i=0;i<total;i++)
     {
      if(OrderSelect(i,SELECT_BY_POS))
        {
         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_SELL)
           {

            sumWeightedAverage+=OrderOpenPrice()*OrderLots();
            sumLotsSell+=OrderLots();

           }

        }

     }

   if(sumLotsSell>0)
     {
      result=NormalizeDouble(sumWeightedAverage/sumLotsSell,digits);
     }

   return result;


  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CommissionSwap()
  {
   int total=OrdersTotal();
   double totalCommissionSwap=0.0;

   for(int i=total-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS))
        {
         Print("Error selecting order ",GetLastError());
        }
      if(OrderSymbol()==Symbol())
        {
         if((OrderType()==OP_BUY) || (OrderType()==OP_SELL))
           {

            totalCommissionSwap+=OrderCommission()+OrderSwap();

           }

        }

     }

   return totalCommissionSwap;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double EquityBalance()
  {

   double equityResult=AccountEquity()+CommissionSwap();

   return NormalizeDouble(equityResult,2);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseByProfit()
  {

   double profit=AccountProfit();
   if(profit>moneyTarget)
     {

      CloseBuyOrders();
      CloseSellOrders();

     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetProfitBuys()
  {
   double sumProfitBuy=0;
   for(int i=0;i<=totalOrders-1;i++)
     {

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_BUY)
           {

            sumProfitBuy+=OrderProfit();

           }

        }

     }// for

   return sumProfitBuy;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetSumLotBuys()
  {
   double sumLotsBuy=0;
   for(int i=0;i<=totalOrders-1;i++)
     {

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_BUY)
           {

            sumLotsBuy+=OrderLots();

           }

        }

     }// for

   return sumLotsBuy;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetSumLotSells()
  {
   double sumLotsSell=0;
   for(int i=0;i<=totalOrders-1;i++)
     {

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_SELL)
           {

            sumLotsSell+=OrderLots();

           }

        }

     }// for

   return sumLotsSell;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetProfitSells()
  {
   double sumProfitSell=0;
   for(int i=0;i<=totalOrders-1;i++)
     {

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_SELL)
           {

            sumProfitSell+=OrderProfit();

           }

        }

     }// for

   return sumProfitSell;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetHighestBuy()
  {

   double highestBuy=-9999;
   for(int i=0;i<=totalOrders-1;i++)
     {
      if(OrderSelect(i,SELECT_BY_POS))
        {
         if(OrderSymbol()!=Symbol()) continue;
         if(OrderType()==OP_BUY)
           {
            if(OrderOpenPrice()>highestBuy)
              {
               highestBuy=OrderOpenPrice();
              }

           }

        }

     }

   return highestBuy;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void HandleCloseOrder()
  {

   double profit=AccountProfit();

   if(hedgeMode)
     {
      if(profit >= 0)
        {
         CloseAllOrders();
         SystemAccounting();
        }
       
     }
   else if(!hedgeMode)
     {

      double profitBuys=GetProfitBuys();
      if(profitBuys>=moneyTarget*sumBuyLots)
        {
         
         CloseBuyOrders();
         
        }

      double profitSells=GetProfitSells();
      if(profitSells >= moneyTarget*sumSellLots)
        {
        
         CloseSellOrders();
         
        }
        
        SystemAccounting();

     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void FiboLevels()
  {
   SystemAccounting();
// HandleCloseOrder updates system account and uses closing order criteria
   HandleCloseOrder();

   UpdateFiboLevels();

// first trade begins here

   if(IsTradingTime() && !hedgeMode)
     {

      if(buyAndSell)
        {
         // Open first buy

         double priceAsk=NormalizeDouble(MarketInfo(NULL,MODE_ASK),digits);
         if((BuyPriceTargetThreshold(priceAsk)) && (totalBuyOrders==0))
           {

            UpdateInitialLot();
            if(OrderSend(Symbol(),OP_BUY,initialLot,priceAsk,slippage,0,0,"GRID INSIDE EA",magicNumber,0,clrLawnGreen)>0)
              {
               lastFiboBuyTarget=priceAsk;
               SystemAccounting();

              }
            else
              {
               int err=GetLastError();
               Print(" Error buying order : (",err,") "+ErrorDescription(err));
              }

           }

         double priceBid=NormalizeDouble(MarketInfo(NULL,MODE_BID),digits);
         if((SellPriceTargetThreshold(priceBid)) && (totalSellOrders==0)) // Open first sell
           {

            UpdateInitialLot();

            if(OrderSend(Symbol(),OP_SELL,initialLot,priceBid,slippage,0,0,"GRID INSIDE EA",magicNumber,0,clrOrangeRed)>0)
              {
               lastFiboSellTarget=priceBid;
               SystemAccounting();

              }
            else
              {
               int err=GetLastError();
               Print(" Error selling order : (",err,") "+ErrorDescription(err));
              }

           }
        }
      else
        {
         if((totalBuyOrders==0) && (totalSellOrders==0))
           {

            double priceAsk=NormalizeDouble(MarketInfo(NULL,MODE_ASK),digits);
            if(priceAsk==fiboBuyPriceTarget)
              {

               UpdateInitialLot();
               if(OrderSend(Symbol(),OP_BUY,initialLot,priceAsk,slippage,0,0,"GRID INSIDE EA",magicNumber,0,clrLawnGreen)>0)
                 {

                  SystemAccounting();

                 }
               else
                 {
                  int err=GetLastError();
                  Print(" Error buying order : (",err,") "+ErrorDescription(err));
                 }

              }

            double priceBid=NormalizeDouble(MarketInfo(NULL,MODE_BID),digits);
            if(priceBid==fiboSellPriceTarget) // Open first sell
              {

               UpdateInitialLot();

               if(OrderSend(Symbol(),OP_SELL,initialLot,priceBid,slippage,0,0,"GRID INSIDE EA",magicNumber,0,clrOrangeRed)>0)
                 {

                  SystemAccounting();

                 }
               else
                 {
                  int err=GetLastError();
                  Print(" Error selling order : (",err,") "+ErrorDescription(err));
                 }

              }

           } // end buy and sell

        }

     }

// now handle the open orders

   HandleFiboLevelsOpenOrder();

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void DisplayInfo()
  {

   double buyProfit=GetProfitBuys();
   double sellProfit=GetProfitSells();
   double accountBalance=AccountBalance();
   double priceBid = MarketInfo(NULL,MODE_BID);
   double priceAsk = MarketInfo(NULL,MODE_ASK);

   double equity=AccountEquity();
   double balance=AccountBalance();
   double freeMargin=AccountFreeMargin();
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   double commissionSwap=CommissionSwap();
   double targetProfitBuy=moneyTarget*sumBuyLots;
   double targetProfitSell=moneyTarget*sumSellLots;

   bool sellPoint=SellPriceTargetThreshold(priceBid);
   bool lastSellPoint=SellPriceTargetThreshold(lastFiboSellTarget);

   bool sellTime=sellPoint && !lastSellPoint;

   bool buyPoint=BuyPriceTargetThreshold(priceAsk);
   bool lastBuyPoint=BuyPriceTargetThreshold(lastFiboSellTarget);

   bool tradeTime=IsTradingTime();

   bool buyTime=buyPoint && !lastBuyPoint;

   Comment(StringFormat("                   "
           +" \nTotal Buy Lot Size = %G "
           +" \nTotal Sell Lot Size = %G "
           +" \nAccount Equity = %G "
           +" \nTotal Comission and Swap = %G "
           +" \nTarget profit buy = %G "
           +" \nTarget profit sell = %G "
           +" \nTime to trade ? = %d "
           +" \nHedge Mode ? = %d "
           +" \nTime to sell ? = %d "
           +" \nTime to buy ? = %d "
           +" \nTotal Buy = %d"
           +" \nTotal Sell = %d"
           +" \nAverage Price Buy = %G"
           +" \nAverage Price Sell = %G"
           +" \nMargin Level = %G"
           +" \nAccount Balance = %G"
           +" \nBuy Profit = %G"
           +" \nSell Profit = %G",
           sumBuyLots,
           sumSellLots,
           currentEquity,
           commissionSwap,
           targetProfitBuy,
           targetProfitSell,
           tradeTime,
           hedgeMode,
           sellTime,
           buyTime,
           totalBuyOrders,
           totalSellOrders,
           averagePriceBuy,
           averagePriceSell,
           marginLevel,
           accountBalance,
           buyProfit,
           sellProfit));

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void HORIZONTAL_LINE(string Name,double price,ENUM_LINE_STYLE style,int width,color c)
  {

   ObjectDelete(Name);
   ObjectCreate(Name,OBJ_HLINE,0,0,price);
   ObjectSetInteger(0,Name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,Name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,Name,OBJPROP_WIDTH,width);

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ARROW(string Name,double Price,int ARROWCODE,color c)
  {
   ObjectDelete(Name);
   ObjectCreate(Name,OBJ_ARROW,0,Time[0],Price,0,0,0,0);
   ObjectSetInteger(0,Name,OBJPROP_ARROWCODE,ARROWCODE);
   ObjectSetInteger(0,Name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,Name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,Name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,Name,OBJPROP_WIDTH,1);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void TEXT(string Name,double Price,string text,int font_size,color c)
  {
   ObjectDelete(Name);
   ObjectCreate(0,Name,OBJ_TEXT,0,Time[0],Price);
   ObjectSetInteger(0,Name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,Name,OBJPROP_FONTSIZE,font_size);
   ObjectSetString(0,Name,OBJPROP_TEXT,text);

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateFiboLevels()
  {
   highestCandleShift= iHighest(NULL,0,MODE_HIGH,20,1);
   lowestCandleShift = iLowest(NULL,0,MODE_LOW,20,1);

   highestCandlePrice= NormalizeDouble(iHigh(NULL,0,highestCandleShift),digits);
   lowestCandlePrice = NormalizeDouble(iLow(NULL,0,lowestCandleShift),digits);

   double fiboLevel1 = NormalizeDouble(0.0,2);
   double fiboLevel2 = NormalizeDouble(0.236,2);
   double fiboLevel3 = NormalizeDouble(0.382,2);
   double fiboLevel4 = NormalizeDouble(0.500,2);
   double fiboLevel5 = NormalizeDouble(0.618,2);
   double fiboLevel6 = NormalizeDouble(0.736,2);
   double fiboLevel7 = NormalizeDouble(1.0,2);


   fiboPriceLevel1 = lowestCandlePrice + (highestCandlePrice-lowestCandlePrice)*fiboLevel1;
   fiboPriceLevel2 = lowestCandlePrice + (highestCandlePrice-lowestCandlePrice)*fiboLevel2;
   fiboPriceLevel3 = lowestCandlePrice + (highestCandlePrice-lowestCandlePrice)*fiboLevel3;
   fiboPriceLevel4 = lowestCandlePrice + (highestCandlePrice-lowestCandlePrice)*fiboLevel4;
   fiboPriceLevel5 = lowestCandlePrice + (highestCandlePrice-lowestCandlePrice)*fiboLevel5;
   fiboPriceLevel6 = lowestCandlePrice + (highestCandlePrice-lowestCandlePrice)*fiboLevel6;
   fiboPriceLevel7 = lowestCandlePrice + (highestCandlePrice-lowestCandlePrice)*fiboLevel7;


   double priceAsk=MarketInfo(NULL,MODE_ASK);

   if(priceAsk<=fiboPriceLevel2)
     {

      if(fiboBuyPriceTarget>(priceAsk+(minGridSpace+pipStep)*myPoint))
        {

         fiboBuyPriceTarget=priceAsk+pipStep*myPoint;

        }

     }
   else if(priceAsk>fiboPriceLevel2)
     {
      fiboBuyPriceTarget=9999;
     }

   double priceBid=MarketInfo(NULL,MODE_BID);

   if(priceBid>fiboPriceLevel6)
     {

      if(fiboSellPriceTarget<(priceBid-(minGridSpace+pipStep)*myPoint))
        {

         fiboSellPriceTarget=priceBid-pipStep*myPoint;

        }

     }
   else
     {
      fiboSellPriceTarget=-9999;
     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool BuyPriceTargetThreshold(double priceBuy)
  {

   bool upperLimit = false;
   bool lowerLimit = false;

   if(targetThreshold==0)
     {
      return (priceBuy==fiboBuyPriceTarget);
     }

   upperLimit = priceBuy < (fiboBuyPriceTarget + targetThreshold*myPoint);
   lowerLimit = priceBuy > (fiboBuyPriceTarget - targetThreshold*myPoint);

   return (upperLimit && lowerLimit);


  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool SellPriceTargetThreshold(double priceSell)
  {

   bool upperLimit = false;
   bool lowerLimit = false;

   if(targetThreshold==0)
     {
      return (priceSell == fiboSellPriceTarget);
     }

   upperLimit = priceSell < (fiboSellPriceTarget + targetThreshold*myPoint);
   lowerLimit = priceSell > (fiboSellPriceTarget - targetThreshold*myPoint);

   return (upperLimit && lowerLimit);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+

void UpdateHedgeLevels()
  {

   double priceAsk=MarketInfo(NULL,MODE_ASK);
   double hedgeDistance = MathAbs(buyWeightedAverage - sellWeightedAverage);
   HedgeSellLevel = sellWeightedAverage + 2*hedgeDistance;
   HedgeBuyLevel = buyWeightedAverage - 2*hedgeDistance;

   if(priceAsk<=HedgeBuyLevel)
     {

      if(hedgeBuyPriceTarget>(priceAsk+(minGridSpace+pipStep)*myPoint))
        {

         hedgeBuyPriceTarget=priceAsk+pipStep*myPoint;

        }

     }
   else if(priceAsk>sellWeightedAverage)
     {
      hedgeBuyPriceTarget=9999;
     }

   double priceBid=MarketInfo(NULL,MODE_BID);

   if(priceBid>=HedgeSellLevel)
     {

      if(hedgeSellPriceTarget<(priceBid-(minGridSpace+pipStep)*myPoint))
        {

         hedgeSellPriceTarget=priceBid-pipStep*myPoint;

        }

     }
   else
     {
      hedgeSellPriceTarget=-9999;
     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void HandleFiboLevelsOpenOrder()
  {

   UpdateFiboLevels();

   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   bool hitMarginLimit=(marginLevel>0) && (marginLevel<marginLevelLimit);

   if(hitMarginLimit)
     {

      hedgeMode=true;

     }

   if(!hedgeMode)
     {

      // New buy order condition
      if((totalBuyOrders>0) && (totalBuyOrders<maxOrders))
        {

         fiboBuyPriceTarget=NormalizeDouble(fiboBuyPriceTarget,5);
         double priceAsk=NormalizeDouble(MarketInfo(NULL,MODE_ASK),digits);

         if((BuyPriceTargetThreshold(priceAsk)) && (!BuyPriceTargetThreshold(lastFiboBuyTarget)))
           {

            double maxHighLow=iATR(NULL,0,atrPeriod,0);

            if(maxHighLow<MaxATR*myPoint)
              {

               double nextBuyLot=GetNextBuyLot();

               if(OrderSend(Symbol(),OP_BUY,nextBuyLot,priceAsk,slippage,0,0,"THE GRID INSIDE EA",magicNumber,0,clrLimeGreen)>0)
                 {
                  lastFiboBuyTarget=priceAsk;
                  SystemAccounting();

                 }
               else
                 {

                  errorMessage=GetLastError();
                  waitNextError=false;
                  Print("  Buy order send error !!!! : (",errorMessage,") "+ErrorDescription(errorMessage));

                 }

              }
           }

        }

      // New sell order condition
      double profitSells = GetProfitSells();
      if((totalSellOrders>0) && (totalSellOrders<maxOrders))
        {

         double priceBid=NormalizeDouble(MarketInfo(NULL,MODE_BID),digits);

         if((SellPriceTargetThreshold(priceBid)) && (!SellPriceTargetThreshold(lastFiboSellTarget)))
           {
            double maxHighLow=iATR(NULL,0,atrPeriod,0);
            double nextSellLot=GetNextSellLot();

            if(maxHighLow<MaxATR*myPoint)
              {
               if(OrderSend(Symbol(),OP_SELL,nextSellLot,priceBid,slippage,0,0,"THE GRID INSIDE EA",magicNumber,0,clrRed)>0)
                 {
                  lastFiboSellTarget=priceBid;
                  SystemAccounting();

                 }
               else
                 {

                  errorMessage=GetLastError();
                  waitNextError=false;
                  Print("  Sell order send error !!!! : (",errorMessage,") "+ErrorDescription(errorMessage));

                 }

              }
           }

        }

     }
   else if(hedgeMode)
     {

      HandleHedgeOrders();

     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void HandleHedgeOrders()
  {

// lock buy and sell

   bool sellLock=  sumSellLots>sumBuyLots;
   bool buyLock = sumBuyLots>sumSellLots;
   
   double marginLevel=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   bool hitMarginLimit=(marginLevel>0) && (marginLevel<marginLevelLimit);
   
   if(hitMarginLimit)
   {
  // lockMode = false;
   }
   
   


   if(!lockMode)
     {

      if(sellLock)
        {

         double buyLotLock=sumSellLots-sumBuyLots;

         double priceAsk=MarketInfo(NULL,MODE_ASK);
         priceAsk=NormalizeDouble(priceAsk,digits);

         if(OrderSend(Symbol(),OP_BUY,buyLotLock,priceAsk,slippage,0,0,"THE GRID INSIDE EA",magicNumber,0,clrLawnGreen)>0)
           {
           
            SystemAccounting();
            totalHedgeOrders = 1;
            lockMode=true;

           }
         else
           {

            errorMessage=GetLastError();
            waitNextError=false;
            Print("  Buy hedge order send error !!!! : (",errorMessage,") "+ErrorDescription(errorMessage));

           }

        }
      else if(buyLock)
        {

         double sellLotLock=sumBuyLots-sumSellLots;
         double priceBid=MarketInfo(NULL,MODE_BID);
         priceBid=NormalizeDouble(priceBid,digits);

         if(OrderSend(Symbol(),OP_SELL,sellLotLock,priceBid,slippage,0,0,"THE GRID INSIDE EA",magicNumber,0,clrLawnGreen)>0)
           {
            SystemAccounting();
            totalHedgeOrders = 1;
            lockMode=true;

           }
         else
           {

            errorMessage=GetLastError();
            waitNextError=false;
            Print("  Buy hedge order send error !!!! : (",errorMessage,") "+ErrorDescription(errorMessage));

           }


        }

     }

   if(lockMode)
     {

      // Adjust hedge levels
      UpdateHedgeLevels();

      double priceAsk=MarketInfo(NULL,MODE_ASK);
      priceAsk=NormalizeDouble(priceAsk,digits);
     
      if((priceAsk==hedgeBuyPriceTarget)&&(hedgeBuyPriceTarget!=lastHedgeBuyTarget))
        {
         double nextBuyLot=GetNextBuyLot();
         if(OrderSend(Symbol(),OP_BUY,nextBuyLot,priceAsk,slippage,0,0,"THE GRID INSIDE EA",magicNumber,0,clrLawnGreen)>0)
           {
            lastHedgeBuyTarget=priceAsk;
            totalHedgeOrders++;
            SystemAccounting();

           }
         else
           {

            errorMessage=GetLastError();
            waitNextError=false;
            Print("  Buy hedge order send error !!!! : (",errorMessage,") "+ErrorDescription(errorMessage));

           }

        }

      double priceBid=MarketInfo(NULL,MODE_BID);
      priceBid=NormalizeDouble(priceBid,digits);

      if((priceBid==hedgeSellPriceTarget)&&(hedgeSellPriceTarget!=lastHedgeSellTarget))
        {
        
         double nextSellLot=GetNextSellLot();
         if(OrderSend(Symbol(),OP_SELL,nextSellLot,priceBid,slippage,0,0,"THE GRID INSIDE EA",magicNumber,0,clrRed)>0)
           {
           
            lastHedgeSellTarget=priceBid;
            totalHedgeOrders++;
            SystemAccounting();

           }
         else
           {

            errorMessage=GetLastError();
            waitNextError=false;
            Print("  Sell hedge order send error !!!! : (",errorMessage,") "+ErrorDescription(errorMessage));

           }

        }

     } 

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateInitialLot()
  {

   if(useMM)
     {

      double checkLotSize=NormalizeDouble(((AccountEquity()*loadPercent)/lotSize),2);

      if(checkLotSize<=minLot)
        {
         initialLot=minLot;

        }
      else
        {

         initialLot=checkLotSize;

        }

     }
   else
     {

      initialLot=fixedLot;

     }

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetNextBuyLot()
  {

   UpdateInitialLot();
   if (lockMode)
   {
   
    totalBuyOrders=totalHedgeOrders;
   
   }
   
   return initialLot*MathFloor(pow(lotFactor,totalBuyOrders));


  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetNextSellLot()
  {

   UpdateInitialLot();
   
   if (lockMode)
   {
   
    totalSellOrders=totalHedgeOrders;
   
   }

   return initialLot*MathFloor(pow(lotFactor,totalSellOrders));

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int TotalBuyOrders()
  {

   int buyCount=0;

   for(int i=0;i<totalOrders;i++)
     {
      if(!OrderSelect(i,SELECT_BY_POS))
        {
         Print(" Error selecting order from TotalBuyOrders ",GetLastError());
        }

      if(OrderSymbol()!=Symbol()) continue;
      if(OrderType()==OP_BUY)
        {

         buyCount++;

        }
     }

   return buyCount;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int TotalSellOrders()
  {

   int sellCount=0;

   for(int i=totalOrders-1;i>=0;i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS))
        {
         Print(" Error selecting order from TotalSellOrders ",GetLastError());
        };

      if(OrderSymbol()!=Symbol()) continue;
      if(OrderType()==OP_SELL)
        {
         sellCount++;
        }
     }

   return sellCount;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CloseBuyOrders()
  {

   bool result=false;

   for(int i=0;i < totalOrders;i++)
     {

      if(OrderSymbol()!=Symbol()) continue;

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderType()==OP_BUY)
           {

            result=OrderClose(OrderTicket(),OrderLots(),MarketInfo(OrderSymbol(),MODE_BID),5,clrLawnGreen);

           }

        }

     }

   return result;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CloseSellOrders()
  {

   bool result=false;

   for(int i=0;i < totalOrders;i++)
     {

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderSymbol()!=Symbol()) continue;

         if(OrderType()==OP_SELL)
           {
            double priceAsk = MarketInfo(OrderSymbol(),MODE_ASK);
            priceAsk = NormalizeDouble(priceAsk,digits);
            result=OrderClose(OrderTicket(),OrderLots(),priceAsk,5,clrRed);

           }
        }
        
     }

   return result;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CloseAllOrders()
  {

   bool result=false;

   for(int i=0;i<totalOrders;i++)
     {

      if(OrderSelect(i,SELECT_BY_POS))
        {

         if(OrderSymbol()!=Symbol()) continue;

         if(OrderType()==OP_SELL)
           {

            result=OrderClose(OrderTicket(),OrderLots(),MarketInfo(OrderSymbol(),MODE_ASK),5,Red);

           }

         if(OrderType()==OP_BUY)
           {

            result=OrderClose(OrderTicket(),OrderLots(),MarketInfo(OrderSymbol(),MODE_BID),5,Red);

           }
        }

     }

   return result;
  }

