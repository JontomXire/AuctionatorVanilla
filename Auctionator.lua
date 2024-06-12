
local AuctionatorVersion = "1.0.0-Vanilla";
local AuctionatorAuthor  = "Zirco; Vanilla adaptation by Nimeral";


local AuctionatorLoaded = false;

local recommendElements		= {};
local auctionsTabElements	= {};

AUCTIONATOR_ENABLE_ALT	= 1;
AUCTIONATOR_OPEN_FIRST	= 0;

local scan_sell_tab_index = 4;

-----------------------------------------

local auctionator_orig_AuctionFrameTab_OnClick;
local auctionator_orig_ContainerFrameItemButton_OnClick;
local auctionator_orig_AuctionFrameAuctions_Update;
local auctionator_orig_AuctionsCreateAuctionButton_OnClick;

local KM_NULL_STATE	= 0;
local KM_PREQUERY	= 1;
local KM_INQUERY	= 2;
local KM_POSTQUERY	= 3;
local KM_ANALYZING	= 4;

local processing_state	= KM_NULL_STATE;
local current_page;

local scandata;
local sorteddata = {};
local basedata;
local best_bid_price;

local currentSellItemName = "";
local currentScanItemName = "";
local currentScanStackSize = 1;
local currentScanTexture = nil;

local auctionator_last_buyoutprice = 1;
local auctionator_last_item_posted = nil;

local bestPriceOurStackSize;

-----------------------------------------

local	BoolToString, BoolToNum, NumToBool, pluralizeIf, round, chatmsg, calcNewPrice, roundPriceDown;
local	val2gsc, priceToString, ItemType2AuctionClass, SubType2AuctionSubclass;

-----------------------------------------


function Auctionator_EventHandler()

--	chatmsg (event);

    if (event == "VARIABLES_LOADED")			then	Auctionator_OnLoad(); 					end;
    if (event == "ADDON_LOADED")				then	Auctionator_OnAddonLoaded(); 			end;
    if (event == "AUCTION_ITEM_LIST_UPDATE")	then	Auctionator_OnAuctionUpdate(); 			end;
    if (event == "AUCTION_OWNED_LIST_UPDATE")	then	Auctionator_OnAuctionOwnedUpdate(); 	end;
    if (event == "AUCTION_HOUSE_SHOW")			then	Auctionator_OnAuctionHouseShow(); 		end;
    if (event == "AUCTION_HOUSE_CLOSED")		then	Auctionator_OnAuctionHouseClosed(); 	end;
    if (event == "NEW_AUCTION_UPDATE")			then	Auctionator_OnNewAuctionUpdate(); 		end;

end

-----------------------------------------


function Auctionator_OnLoad()

    chatmsg("Auctionator Loaded");

    AuctionatorLoaded = true;

    sorteddata = {};
    Auctionator_ScrollbarUpdate();
    Auctionator_SetMessage ("Drag an item to the Auction Item area\n\nto see recommended pricing information");

end

-----------------------------------------

function Auctionator_OnAddonLoaded()

    if (string.lower (arg1) == "blizzard_auctionui") then
        Auctionator_AddScanSellTab();
        Auctionator_SetupHookFunctions();

        auctionsTabElements[1]  = AuctionsScrollFrame;
        auctionsTabElements[2]  = AuctionsButton1;
        auctionsTabElements[3]  = AuctionsButton2;
        auctionsTabElements[4]  = AuctionsButton3;
        auctionsTabElements[5]  = AuctionsButton4;
        auctionsTabElements[6]  = AuctionsButton5;
        auctionsTabElements[7]  = AuctionsButton6;
        auctionsTabElements[8]  = AuctionsButton7;
        auctionsTabElements[9]  = AuctionsButton8;
        auctionsTabElements[10] = AuctionsButton9;
        auctionsTabElements[11] = AuctionsQualitySort;
        auctionsTabElements[12] = AuctionsDurationSort;
        auctionsTabElements[13] = AuctionsHighBidderSort;
        auctionsTabElements[14] = AuctionsBidSort;
        auctionsTabElements[15] = AuctionsCancelAuctionButton;

        recommendElements[1] = getglobal ("Auctionator_Recommend_Text");
        recommendElements[2] = getglobal ("Auctionator_RecommendPerItem_Text");
        recommendElements[3] = getglobal ("Auctionator_RecommendPerItem_Price");
        recommendElements[4] = getglobal ("Auctionator_RecommendPerStack_Text");
        recommendElements[5] = getglobal ("Auctionator_RecommendPerStack_Price");
        recommendElements[6] = getglobal ("Auctionator_Recommend_Basis_Text");
        recommendElements[7] = getglobal ("Auctionator_RecommendItem_Tex");
        recommendElements[8] = getglobal ("Auctionator_BestBidPerItem_Price");
        recommendElements[9] = getglobal ("Auctionator_BestBid_Text");

        Auctionator_HideElems(recommendElements);
    end
end


-----------------------------------------


function Auctionator_AuctionFrameTab_OnClick(index)

    if (not index) then
        index = this:GetID();
    end

    if (index == scan_sell_tab_index) then
        AuctionatorScanSellFrame:Show();
        auctionator_orig_AuctionFrameTab_OnClick(3);
        Auctionator_HideElems(auctionsTabElements);

        PanelTemplates_SetTab(AuctionFrame, scan_sell_tab_index);

        AuctionFrame:EnableMouse(false);

        if (currentScanItemName ~= "") then
            Auctionator_CalcBaseData();
        end
    else
        AuctionatorScanSellFrame:Hide();
        Auctionator_ShowElems(auctionsTabElements);
        auctionator_orig_AuctionFrameTab_OnClick(index);
        auctionator_last_item_posted = nil;
    end

end

-----------------------------------------


function Auctionator_ContainerFrameItemButton_OnModifiedClick (button)

    if (	AUCTIONATOR_ENABLE_ALT == 0
        or  not	AuctionFrame:IsShown()
        or	not	IsAltKeyDown())
    then
        return auctionator_orig_ContainerFrameItemButton_OnModifiedClick (button);
    end;

    if (PanelTemplates_GetSelectedTab (AuctionFrame) ~= scan_sell_tab_index) then
        AuctionFrameTab_OnClick (scan_sell_tab_index);
    end


    PickupContainerItem(this:GetParent():GetID(), this:GetID());

    local infoType = GetCursorInfo()

    if (infoType == "item") then
        ClickAuctionSellItemButton();
        ClearCursor();
    end

end


-----------------------------------------

function Auctionator_AuctionFrameAuctions_Update()

    auctionator_orig_AuctionFrameAuctions_Update();

    if (PanelTemplates_GetSelectedTab (AuctionFrame) == scan_sell_tab_index  and	AuctionFrame:IsShown()) then
        Auctionator_HideElems (auctionsTabElements);
    end


end

-----------------------------------------
-- Intercept the Create Auction click so
-- that we can note the auction values
-----------------------------------------

function Auctionator_AuctionsCreateAuctionButton_OnClick()

    if (PanelTemplates_GetSelectedTab(AuctionFrame) == scan_sell_tab_index  and AuctionFrame:IsShown()) then
        auctionator_last_buyoutprice = MoneyInputFrame_GetCopper(BuyoutPrice);
        auctionator_last_item_posted = currentSellItemName;
    end

    auctionator_orig_AuctionsCreateAuctionButton_OnClick();

end

-----------------------------------------

function Auctionator_OnAuctionOwnedUpdate ()

    if (auctionator_last_item_posted) then

        Auctionator_Recommend_Text:SetText ("Auction Created for "..auctionator_last_item_posted);

        MoneyFrame_Update("Auctionator_RecommendPerStack_Price", auctionator_last_buyoutprice);

        Auctionator_RecommendPerStack_Price:Show();
        Auctionator_RecommendPerItem_Price:Hide();
        Auctionator_RecommendPerItem_Text:Hide();
        Auctionator_Recommend_Basis_Text:Hide();
    end

end

-----------------------------------------

function Auctionator_OnNewAuctionUpdate()


end

-----------------------------------------

function Auctionator_SetupHookFunctions ()

    auctionator_orig_AuctionFrameTab_OnClick = AuctionFrameTab_OnClick;
    AuctionFrameTab_OnClick = Auctionator_AuctionFrameTab_OnClick;

    auctionator_orig_ContainerFrameItemButton_OnModifiedClick = ContainerFrameItemButton_OnModifiedClick;
    ContainerFrameItemButton_OnModifiedClick = Auctionator_ContainerFrameItemButton_OnModifiedClick;

    auctionator_orig_AuctionFrameAuctions_Update = AuctionFrameAuctions_Update;
    AuctionFrameAuctions_Update = Auctionator_AuctionFrameAuctions_Update;

    auctionator_orig_AuctionsCreateAuctionButton_OnClick = AuctionsCreateAuctionButton_OnClick;
    AuctionsCreateAuctionButton_OnClick = Auctionator_AuctionsCreateAuctionButton_OnClick;

end

-----------------------------------------

function Auctionator_AddScanSellTab()

    local n = AuctionFrame.numTabs + 1;

    scan_sell_tab_index = n;

    local framename = "AuctionFrameTab"..n;

    local frame = CreateFrame("Button", framename, AuctionFrame, "AuctionTabTemplate");

    setglobal(framename, frame);
    frame:SetID(n);
    frame:SetText("Scan/Sell");
    frame:SetPoint("LEFT", getglobal("AuctionFrameTab"..(n-1)), "RIGHT", -8, 0);
    frame:Show();

    PanelTemplates_SetNumTabs(AuctionFrame, n);
    PanelTemplates_EnableTab(AuctionFrame, n);

end

-----------------------------------------

function Auctionator_HideElems (tt)

    if (not tt) then
        return;
    end

    for i,x in ipairs(tt) do
        x:Hide();
    end
end

-----------------------------------------

function Auctionator_ShowElems (tt)

    for i,x in ipairs(tt) do
        x:Show();
    end
end

-----------------------------------------

function Auctionator_StartScan(auctionItemName, auctionCount, auctionTexture)

    sorteddata = {};
    Auctionator_ScrollbarUpdate();

    currentScanItemName  = auctionItemName;
    currentScanStackSize = auctionCount;
    currentScanTexture   = auctionTexture;

    Auctionator_RecommendPerItem_Price:Hide();
    Auctionator_RecommendPerStack_Price:Hide();
    Auctionator_BestBidPerItem_Price:Hide();

    basedata = nil;
    best_bid_price = nil;

    SortAuctionItems("list", "buyout");

    if (IsAuctionSortReversed("list", "buyout")) then
        SortAuctionItems("list", "buyout");
    end

    current_page = 0;
    processing_state = KM_PREQUERY;

    scandata = {};

end

-----------------------------------------

function Auctionator_OnAuctionUpdate ()

    if (processing_state ~= KM_POSTQUERY) then
        return;
    end

    processing_state = KM_ANALYZING;

    local numBatchAuctions, totalAuctions = GetNumAuctionItems("list");

    if (totalAuctions >= 50) then
        Auctionator_SetMessage ("Scanning auctions: page "..current_page);
    end

    if (numBatchAuctions > 0) then
        local x;

        for x = 1, numBatchAuctions do
            local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, owner = GetAuctionItemInfo("list", x);

            if (name == currentScanItemName) then
                if (buyoutPrice > 0) then
                    local sd = {};

                    sd["stackSize"]   = count;
                    sd["buyoutPrice"] = buyoutPrice;
                    sd["owner"]       = owner;

                    tinsert (scandata, sd);
                end

                if (3 > GetAuctionItemTimeLeft("list", x)) then
                    local bid_price;

                    if ((nil == bidAmount) or (0 == bidAmount)) then
                        bid_price = round(minBid / count);
                    else
                        bid_price = round((bidAmount + minIncrement) / count);
                    end

                    if ((nil == best_bid_price) or (best_bid_price > bid_price)) then
                        best_bid_price = bid_price;
                    end
                end

                if (nil == currentScanTexture) then
                    currentScanTexture = texture;
                end
            end
        end
    end

    if (numBatchAuctions == 50) then
        processing_state = KM_PREQUERY;
    else
        if (table.getn (scandata) > 0) then
            Auctionator_Process_Scandata ();
            Auctionator_CalcBaseData();
        else
            Auctionator_SetMessage ("No auctions were found for \n\n"..currentScanItemName);
        end

        processing_state = KM_NULL_STATE;
    end



end

-----------------------------------------

function Auctionator_SetMessage (msg)
    Auctionator_HideElems (recommendElements);
    Auctionator_HideElems (overallElements);

    AuctionatorMessage:SetText (msg);
    AuctionatorMessage:Show();
end

-----------------------------------------

function Auctionator_Process_Scandata ()

    sorteddata = {};

    if (scandata == nil) then
        return;
    end;

    ----- Condense the scan data into a table that has only a single entry per stacksize/price combo

    local i,sd;
    local conddata = {};

    for i,sd in ipairs (scandata) do

        local key = "_"..sd.stackSize.."_"..sd.buyoutPrice;


        if (conddata[key]) then
            conddata[key].count = conddata[key].count + 1;
        else
            local data = {};

            data.stackSize   = sd.stackSize;
            data.buyoutPrice = sd.buyoutPrice;
            data.itemPrice   = sd.buyoutPrice / sd.stackSize;
            data.count       = 1;
            data.numYours    = 0;

            conddata[key] = data;
        end

        if (sd.owner == UnitName("player")) then
            conddata[key].numYours = conddata[key].numYours + 1;
        end

    end

    ----- create a table of these entries sorted by itemPrice

    local n = 1;
    for i,v in pairs (conddata) do
        sorteddata[n] = v;
        n = n + 1;
    end


    table.sort (sorteddata, function(a,b) return a.itemPrice < b.itemPrice; end);

end

-----------------------------------------

function Auctionator_CalcBaseData ()

    local absoluteBest;

    local j, sd;

    ----- find the best price per stacksize and overall -----

    for j,sd in ipairs(sorteddata) do
        if ((absoluteBest == nil) or (absoluteBest.itemPrice > sd.itemPrice)) then
            absoluteBest = sd;
        end
    end

    basedata = absoluteBest;

    Auctionator_UpdateRecommendation();
end

-----------------------------------------

function Auctionator_UpdateRecommendation ()

    if (basedata) then
        local newBuyoutPrice = basedata.itemPrice * currentScanStackSize;

        if (basedata.numYours < basedata.count) then
            newBuyoutPrice = calcNewPrice (newBuyoutPrice);
        end

        local newStartPrice = calcNewPrice(round(newBuyoutPrice *0.95));

        Auctionator_ShowElems (recommendElements);
        AuctionatorMessage:Hide();

        Auctionator_Recommend_Text:SetText ("Recommended Buyout Price");
        Auctionator_RecommendPerStack_Text:SetText ("for your stack of "..currentScanStackSize);

        if (currentScanTexture) then
            Auctionator_RecommendItem_Tex:SetNormalTexture (currentScanTexture);
            if (currentScanStackSize > 1) then
                Auctionator_RecommendItem_TexCount:SetText (currentScanStackSize);
                Auctionator_RecommendItem_TexCount:Show();
            else
                Auctionator_RecommendItem_TexCount:Hide();
            end
        else
            Auctionator_RecommendItem_Tex:Hide();
        end

        MoneyFrame_Update("Auctionator_RecommendPerItem_Price",  round(newBuyoutPrice / currentScanStackSize));
        MoneyFrame_Update("Auctionator_RecommendPerStack_Price", round(newBuyoutPrice));

        MoneyInputFrame_SetCopper (BuyoutPrice, newBuyoutPrice);
        MoneyInputFrame_SetCopper (StartPrice,  newStartPrice);

        Auctionator_ScrollbarUpdate();

        if (basedata.stackSize == sorteddata[1].stackSize and basedata.buyoutPrice == sorteddata[1].buyoutPrice) then
            Auctionator_Recommend_Basis_Text:SetText ("(based on cheapest)");
        elseif (bestPriceOurStackSize and basedata.stackSize == bestPriceOurStackSize.stackSize and basedata.buyoutPrice == bestPriceOurStackSize.buyoutPrice) then
            Auctionator_Recommend_Basis_Text:SetText ("(based on cheapest stack of the same size)");
        else
            Auctionator_Recommend_Basis_Text:SetText ("(based on auction selected below)");
        end
    end

    if (best_bid_price == nil) then
        Auctionator_BestBid_Text:Hide();
        Auctionator_BestBidPerItem_Price:Hide();
    else
        MoneyFrame_Update("Auctionator_BestBidPerItem_Price", best_bid_price);
        Auctionator_BestBid_Text:Show();
        Auctionator_BestBidPerItem_Price:Show();
    end

end



-----------------------------------------

function Auctionator_OnAuctionHouseShow()

    if (AUCTIONATOR_OPEN_FIRST ~= 0) then
        AuctionFrameTab_OnClick(scan_sell_tab_index);
    end

end

-----------------------------------------

function Auctionator_OnAuctionHouseClosed()

    AuctionatorOptionsFrame:Hide();
    AuctionatorDescriptionFrame:Hide();
    AuctionatorScanSellFrame:Hide();

end



-----------------------------------------

function Auctionator_OnUpdate(self, elapsed)

    Auctionator_Idle (self, elapsed);

end


-----------------------------------------

function Auctionator_Idle(self, elapsed)

    if (self.TimeSinceLastUpdate == nil) then
        self.TimeSinceLastUpdate = 0;
    end;
    self.TimeSinceLastUpdate = self.TimeSinceLastUpdate + 0.1;--elapsed;

    if (AuctionatorMessage == nil) then
        return;
    end;

    if (self.TimeSinceLastUpdate > 0.25) then

        self.TimeSinceLastUpdate = 0;

        ------- check whether to send a new auction query to get the next page -------

        if (processing_state == KM_PREQUERY) then
            if (CanSendAuctionQuery()) then
                processing_state = KM_IN_QUERY;
                QueryAuctionItems (currentScanItemName, "", "", nil, nil, nil, current_page, nil, nil);
                processing_state = KM_POSTQUERY;
                current_page = current_page + 1;
            end
        end
    end

    ------- check whether the "sell" item has changed -------

    local auctionItemName, auctionTexture, auctionCount = GetAuctionSellItemInfo();

    if (auctionItemName == nil) then
        auctionItemName = "";
        auctionCount	= 0;
    end

    if (currentSellItemName ~= auctionItemName) then
        if (((processing_state == KM_NULL_STATE) or (currentSellItemName == currentScanItemName)) and
            (PanelTemplates_GetSelectedTab (AuctionFrame) == scan_sell_tab_index)) then
            if (auctionItemName ~= "") then
                Auctionator_StartScan(auctionItemName, auctionCount, auctionTexture);
            elseif (currentSellItemName == currentScanItemName) then
                currentScanItemName = "";
                sorteddata = {};
                Auctionator_ScrollbarUpdate();
                processing_state = KM_NULL_STATE;
                Auctionator_SetMessage ("Drag an item to the Auction Item area\n\nto see recommended pricing information");
            else
                -- Leave the current text as is, we are probably doing a manual scan.
            end
        end

        currentSellItemName = auctionItemName;
    end

end


-----------------------------------------

function Auctionator_ScrollbarUpdate()

    local line;				-- 1 through 12 of our window to scroll
    local dataOffset;		-- an index into our data calculated from the scroll offset

    local numrows = table.getn (sorteddata);

    if (numrows == nil) then
        numrows = 0
    end

    FauxScrollFrame_Update (AuctionatorScrollFrame, numrows, 10, 16);

    for line = 1,10 do

        dataOffset = line + FauxScrollFrame_GetOffset (AuctionatorScrollFrame);

        local lineEntry = getglobal ("AuctionatorEntry"..line);

        lineEntry:SetID(dataOffset);

        if dataOffset <= numrows and sorteddata[dataOffset] then

            local data = sorteddata[dataOffset];

            local lineEntry_avail	= getglobal("AuctionatorEntry"..line.."_Availability");
            local lineEntry_comm	= getglobal("AuctionatorEntry"..line.."_Comment");
            local lineEntry_stack	= getglobal("AuctionatorEntry"..line.."_StackPrice");

            if (data.itemPrice == basedata.itemPrice and data.stackSize == basedata.stackSize) then
                lineEntry:LockHighlight();
            else
                lineEntry:UnlockHighlight();
            end

            if ( data.stackSize == currentScanStackSize ) then	lineEntry_avail:SetTextColor (0.2, 0.9, 0.2);
            else													lineEntry_avail:SetTextColor (1.0, 1.0, 1.0);
            end;


            if (data.numYours == 0) then
                lineEntry_comm:SetText("");
            elseif (data.numYours == data.count) then
                lineEntry_comm:SetText("yours");
            else
                lineEntry_comm:SetText("yours: "..data.numYours);
            end;


            local tx = string.format ("%i %s of %i", data.count, pluralizeIf ("stack", data.count), data.stackSize);

            MoneyFrame_Update ("AuctionatorEntry"..line.."_PerItem_Price", round(data.buyoutPrice/data.stackSize) );

            lineEntry_avail:SetText (tx);
            lineEntry_stack:SetText (priceToString(data.buyoutPrice));

            lineEntry:Show();
        else
            lineEntry:Hide();
        end
    end
end

-----------------------------------------

function Auctionator_EntryOnClick()
    local entryIndex = this:GetID();

    basedata = sorteddata[entryIndex];

    Auctionator_UpdateRecommendation();

    PlaySound ("igMainMenuOptionCheckBoxOn");
end

-----------------------------------------

function AuctionatorMoneyFrame_OnLoad()

    this.small = 1;
    SmallMoneyFrame_OnLoad();
    MoneyFrame_SetType("AUCTION");

end

-----------------------------------------

function Auctionator_ShowOptionsFrame()

    AuctionatorOptionsFrame:Show();
    AuctionatorOptionsFrame:SetBackdropColor(0,0,0,100);

    AuctionatorConfigFrameTitle:SetText ("Auctionator Options for "..UnitName("player"));

    local expText = "<html><body>"
                    .."<h1>What is Auctionator?</h1><br/>"
                    .."<p>"
                    .."Figuring out a good buyout price when posting auctions can be tedious and time-consuming.  If you're like most people, you first browse the current "
                    .."auctions to get a sense of how much your item is currently selling for.  Then you undercut the lowest price by a bit.  If you're creating multiple auctions "
                    .."you're bouncing back and forth between the Browse tab and the Auctions tab, doing lots of division in "
                    .."your head, and doing lots of clicking and typing."
                    .."</p><br/><h1>How it works</h1><br/><p>"
                    .."Auctionator makes this whole process easy and streamlined.  When you select an item to auction, Auctionator displays a summary of all the current auctions for "
                    .."that item sorted by per-item price.  Auctionator also calculates a recommended buyout price based on the cheapest per-item price for your item.  If you're "
                    .."selling a stack rather than a single item, Auctionator bases its recommended buyout price on the cheapest stack of the same size."
                    .."</p><br/><p>"
                    .."If you don't like Auctionator's recommendation, you can click on any line in the summary and Auctionator will recalculate the recommended buyout price based "
                    .."on that auction.  Of course, you can always override Auctionator's recommendation by just typing in your own buyout price."
                    .."</p><br/><p>"
                    .."With Auctionator, creating an auction is usually just a matter of picking an item to auction and clicking the Create Auction button."
                    .."</p>"
                    .."</body></html>"
                    ;



    AuctionatorExplanation:SetText ("Auctionator is an addon designed to make it easier and faster to setup your auctions at the auction house.");
    AuctionatorDescriptionHTML:SetText (expText);
    AuctionatorDescriptionHTML:SetSpacing (3);

    AuctionatorVersionText:SetText ("Version: "..AuctionatorVersion);


    AuctionatorOption_Enable_Alt:SetChecked(NumToBool(AUCTIONATOR_ENABLE_ALT));
    AuctionatorOption_Open_First:SetChecked(NumToBool(AUCTIONATOR_OPEN_FIRST));

end

-----------------------------------------

function Auctionator_ScanByName()

    local scanName = AuctionatorScanName:GetText();

    if ("" == scanName) then
        local auctionItemName, auctionTexture, auctionCount = GetAuctionSellItemInfo();

        if (nil ~= auctionItemName) then
            AuctionatorScanName:SetText(auctionItemName);
            BrowseName:SetText(auctionItemName);
            Auctionator_StartScan(auctionItemName, auctionCount, auctionTexture);
        end
    else
        BrowseName:SetText(scanName);
        Auctionator_StartScan(scanName, 1, nil);
    end

end

-----------------------------------------

function AuctionatorOptionsSave()

    AUCTIONATOR_ENABLE_ALT = BoolToNum(AuctionatorOption_Enable_Alt:GetChecked ());
    AUCTIONATOR_OPEN_FIRST = BoolToNum(AuctionatorOption_Open_First:GetChecked ());

end

-----------------------------------------

function Auctionator_ShowTooltip_EnableAlt()

    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM");
    GameTooltip:SetText("Enable alt-key shortcut", 0.9, 1.0, 1.0);
    GameTooltip:AddLine("If this option is checked, holding the Alt key down while clicking an item in your bags will switch to the Auctionator panel, place the item in the Auction Item area, and start the scan.", 0.5, 0.5, 1.0, 1);
    GameTooltip:Show();

end

-----------------------------------------

function Auctionator_ShowTooltip_OpenFirst()

    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM");
    GameTooltip:SetText("Automatically open Auctionator panel", 0.9, 1.0, 1.0);
    GameTooltip:AddLine("If this option is checked, the Auctionator panel will display first whenever you open the Auction House window.", 0.5, 0.5, 1.0, 1);
    GameTooltip:Show();

end



--[[***************************************************************

    All function below here are local utility functions.
    These should be declared local at the top of this file.

--*****************************************************************]]


function BoolToString (b)
    if (b) then
        return "true";
    end

    return "false";
end

-----------------------------------------

function BoolToNum (b)
    if (b) then
        return 1;
    end

    return 0;
end

-----------------------------------------

function NumToBool (n)
    if (n == 0) then
        return false;
    end

    return true;
end

-----------------------------------------

function pluralizeIf (word, count)

    if (count and count == 1) then
        return word;
    else
        return word.."s";
    end
end

-----------------------------------------

function round (v)
    return math.floor (v + 0.5);
end

-----------------------------------------

function chatmsg (msg)
    if (DEFAULT_CHAT_FRAME) then
        DEFAULT_CHAT_FRAME:AddMessage (msg);
    end
end

-----------------------------------------

function calcNewPrice (price)

    if	(price > 2000000)	then return roundPriceDown (price, 10000, 10000);	end;
    if	(price > 1000000)	then return roundPriceDown (price,  2500,  2500);	end;
    if	(price >  500000)	then return roundPriceDown (price,  1000,  1000);	end;
    if	(price >   50000)	then return roundPriceDown (price,   500,   500);	end;
    if	(price >   10000)	then return roundPriceDown (price,   500,   200);	end;
    if	(price >    2000)	then return roundPriceDown (price,   100,    50);	end;
    if	(price >     100)	then return roundPriceDown (price,    10,     5);	end;
    if	(price >       0)	then return math.floor (price - 1);	end;

    return 0;
end

-----------------------------------------
-- roundPriceDown - rounds a price down to the next lowest multiple of a.
--				  - if the result is not at least b lower, rounds down by a again.
--
--	examples:  	(128790, 500, 250)  ->  128500
--				(128700, 500, 250)  ->  128000
--				(128400, 500, 250)  ->  128000
-----------------------------------------

function roundPriceDown (price, a, b)

    local newprice = math.floor(price / a) * a;

    if ((price - newprice) < b) then
        newprice = newprice - a;
    end

    return newprice;

end

-----------------------------------------

function val2gsc (v)
    local rv = round(v)

    local g = math.floor (rv/10000);

    rv = rv - g*10000;

    local s = math.floor (rv/100);

    rv = rv - s*100;

    local c = rv;

    return g, s, c
end

-----------------------------------------

function priceToString (val)

    local gold, silver, copper  = val2gsc(val);

    local st = "";


    if (gold ~= 0) then
        st = gold.."g ";
    end


    if (st ~= "") then
        st = st..format("%02is ", silver);
    elseif (silver ~= 0) then
        st = st..silver.."s ";
    end


    if (st ~= "") then
        st = st..format("%02ic", copper);
    elseif (copper ~= 0) then
        st = st..copper.."c";
    end

    return st;
end

-----------------------------------------

function ItemType2AuctionClass(itemType)
    local itemClasses = { GetAuctionItemClasses() };
    if (itemClasses ~= nil) then
        if table.getn (itemClasses) > 0 then
        local itemClass;
            for x, itemClass in pairs(itemClasses) do
                if (itemClass == itemType) then
                    return x;
                end
            end
        end
    else chatmsg ("Can't GetAuctionItemClasses"); end
end

-----------------------------------------

function SubType2AuctionSubclass(auctionClass, itemSubtype)
    local itemClasses = { GetAuctionItemSubClasses(auctionClass.number) };
    if itemClasses.n > 0 then
    local itemClass;
        for x, itemClass in pairs(itemClasses) do
            if (itemClass == itemSubtype) then
                return x;
            end
        end
    end
end

function relevel(frame) --Local
    local myLevel = frame:GetFrameLevel() + 1
    local children = { frame:GetChildren() }
    for _,child in pairs(children) do
        child:SetFrameLevel(myLevel)
        relevel(child)
    end
end





