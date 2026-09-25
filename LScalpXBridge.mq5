//+------------------------------------------------------------------+
//|  LScalpXBridge.mq5                                                |
//|  Attach this to ONE chart in your MT5 terminal (the symbol you    |
//|  configured in the app's Scanner screen). It:                     |
//|    1) sends a heartbeat (balance/equity) every HeartbeatSeconds   |
//|    2) polls your backend for pending scanner trades and opens them|
//|    3) reports fills/closes back to the backend                    |
//|                                                                    |
//|  Before running: MT5 -> Tools -> Options -> Expert Advisors ->    |
//|  "Allow WebRequest for listed URL" -> add your backend's URL.     |
//+------------------------------------------------------------------+
#property strict

input string BackendUrl      = "https://your-backend.example.com"; // no trailing slash
input string EaSharedSecret  = "change-me-too";   // must match backend .env EA_SHARED_SECRET
input string Mt5LoginId      = "12345678";        // must match what you entered in the app
input int    HeartbeatSeconds = 30;
input int    PollSeconds      = 5;

datetime lastHeartbeat = 0;
datetime lastPoll = 0;

int OnInit()
  {
   Print("LScalpXBridge started for login ", Mt5LoginId);
   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   datetime now = TimeCurrent();

   if(now - lastHeartbeat >= HeartbeatSeconds)
     {
      SendHeartbeat();
      lastHeartbeat = now;
     }

   if(now - lastPoll >= PollSeconds)
     {
      PollAndExecutePendingTrades();
      lastPoll = now;
     }
  }

//--- Reports balance/equity so the app shows real account numbers
void SendHeartbeat()
  {
   string url = BackendUrl + "/api/trades/heartbeat";
   string body = StringFormat("{\"mt5_login\":\"%s\",\"balance\":%.2f,\"equity\":%.2f}",
                               Mt5LoginId, AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   PostJson(url, body);
  }

//--- Fetches scanner-generated trades this account still needs to open
void PollAndExecutePendingTrades()
  {
   string url = BackendUrl + "/api/trades/pending?mt5_login=" + Mt5LoginId;
   string headers = "X-EA-Secret: " + EaSharedSecret + "\r\n";
   char post[]; char result[]; string resultHeaders;
   ResetLastError();
   int res = WebRequest("GET", url, headers, 5000, post, result, resultHeaders);
   if(res == -1)
     {
      Print("WebRequest failed (", GetLastError(), "). Did you allow this URL in Options -> Expert Advisors?");
      return;
     }
   string json = CharArrayToString(result);
   // Minimal parsing: this EA expects the backend's {"trades":[...]} shape.
   // For anything beyond simple market-order execution, extend this parser
   // or swap in a JSON library (e.g. the free "JAson" include).
   ExecuteTradesFromJson(json);
  }

void ExecuteTradesFromJson(string json)
  {
   int pos = 0;
   while(true)
     {
      int idIdx = StringFind(json, "\"id\":\"", pos);
      if(idIdx == -1) break;
      int idStart = idIdx + 6;
      int idEnd = StringFind(json, "\"", idStart);
      string id = StringSubstr(json, idStart, idEnd - idStart);

      string symbol = ExtractField(json, "symbol", idEnd);
      string side   = ExtractField(json, "side", idEnd);
      string lotStr = ExtractField(json, "lot", idEnd);
      double lot = StringToDouble(lotStr);

      OpenMarketOrder(id, symbol, side, lot);
      pos = idEnd;
     }
  }

string ExtractField(string json, string field, int fromPos)
  {
   int idx = StringFind(json, "\"" + field + "\":\"", fromPos);
   bool quoted = true;
   if(idx == -1)
     {
      idx = StringFind(json, "\"" + field + "\":", fromPos);
      quoted = false;
     }
   if(idx == -1) return "";
   int start = idx + StringLen(field) + (quoted ? 4 : 3);
   int end = quoted ? StringFind(json, "\"", start) : StringFind(json, ",", start);
   if(end == -1) end = StringFind(json, "}", start);
   return StringSubstr(json, start, end - start);
  }

void OpenMarketOrder(string tradeId, string symbol, string side, double lot)
  {
   MqlTradeRequest request; MqlTradeResult result;
   ZeroMemory(request); ZeroMemory(result);

   double price = (side == "BUY") ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = symbol;
   request.volume   = lot;
   request.type     = (side == "BUY") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price    = price;
   request.deviation = 10;
   request.magic    = 990011;
   request.comment  = "LScalpX:" + tradeId;

   if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE)
     {
      Print("Opened ", side, " ", symbol, " lot ", lot, " ticket ", result.order);
      ReportOpened(tradeId, result.order);
     }
   else
     {
      Print("OrderSend failed for trade ", tradeId, " retcode=", result.retcode);
     }
  }

void ReportOpened(string tradeId, ulong ticket)
  {
   string url = BackendUrl + "/api/trades/" + tradeId + "/opened";
   string body = StringFormat("{\"mt5_ticket\":\"%I64u\"}", ticket);
   PostJson(url, body);
  }

void PostJson(string url, string body)
  {
   string headers = "Content-Type: application/json\r\nX-EA-Secret: " + EaSharedSecret + "\r\n";
   char post[]; StringToCharArray(body, post, 0, StringLen(body));
   char result[]; string resultHeaders;
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);
   if(res == -1)
      Print("PostJson failed (", GetLastError(), ") for ", url);
  }
//+------------------------------------------------------------------+
