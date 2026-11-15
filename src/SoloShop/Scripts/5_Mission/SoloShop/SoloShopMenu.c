const int SOLO_SHOP_CARDS = 15;

class SoloShopMenu extends UIScriptedMenu
{
	protected TextWidget m_SoloPlayerName;
	protected TextWidget m_SoloBalance;
	protected TextWidget m_SoloStatus;
	protected TextWidget m_SoloItemName;
	protected TextWidget m_SoloOwned;
	protected EditBoxWidget m_SoloSearch;
	protected TextWidget m_SoloCategoryName;
	protected ButtonWidget m_SoloCategoryPrev;
	protected ButtonWidget m_SoloCategoryNext;
	protected TextWidget m_SoloPageText;
	protected ButtonWidget m_SoloPagePrev;
	protected ButtonWidget m_SoloPageNext;
	protected TextWidget m_SoloQuantity;
	protected ButtonWidget m_SoloMinus;
	protected ButtonWidget m_SoloPlus;
	protected ButtonWidget m_SoloBuy;
	protected ButtonWidget m_SoloCashOut;
	protected ButtonWidget m_SoloPayIn;
	protected EditBoxWidget m_SoloCashAmount;
	protected ButtonWidget m_SoloSell;
	protected ButtonWidget m_SoloClose;
	protected ButtonWidget m_SoloNavMarket;
	protected ButtonWidget m_SoloNavInventory;
	protected ButtonWidget m_SoloNavVehicles;
	protected Widget m_SoloBuyBack;
	protected TextWidget m_SoloBuyLabel;
	protected TextWidget m_SoloSellLabel;
	protected ref array<TextWidget> m_SoloCentered;
	protected Widget m_SoloNavMarketBack;
	protected Widget m_SoloNavInventoryBack;
	protected Widget m_SoloNavVehiclesBack;
	protected ItemPreviewWidget m_SoloPreview;
	protected EntityAI m_SoloPreviewItem;

	protected ref array<Widget> m_SoloCards;
	protected ref array<Widget> m_SoloCardOwned;
	protected ref array<ItemPreviewWidget> m_SoloCardPreviews;
	protected ref array<TextWidget> m_SoloCardNames;
	protected ref array<TextWidget> m_SoloCardPrices;
	protected ref array<ButtonWidget> m_SoloCardButtons;
	protected ref array<EntityAI> m_SoloCardItems;
	protected ref array<int> m_SoloFiltered;

	protected int m_SoloSeenCategories = -1;
	protected int m_SoloSeenItems = -1;
	protected int m_SoloSeenSell = -1;
	protected int m_SoloSeenStatus = -1;
	protected bool m_SoloInventoryMode;
	protected bool m_SoloAwaitingResult;
	protected int m_SoloCategoryIndex;
	protected string m_SoloLastCategory = "";
	protected int m_SoloPage;
	protected int m_SoloSelected = -1;
	protected int m_SoloAmount = 1;
	protected string m_SoloSearchText = "";

	override Widget Init()
	{
		if (layoutRoot)
			return layoutRoot;

		layoutRoot = GetGame().GetWorkspace().CreateWidgets("SoloShop/gui/layouts/shop.layout");
		m_SoloCards = new array<Widget>;
		m_SoloCardOwned = new array<Widget>;
		m_SoloCardPreviews = new array<ItemPreviewWidget>;
		m_SoloCardNames = new array<TextWidget>;
		m_SoloCardPrices = new array<TextWidget>;
		m_SoloCardButtons = new array<ButtonWidget>;
		m_SoloCardItems = new array<EntityAI>;
		m_SoloFiltered = new array<int>;
		if (!layoutRoot)
		{
			Print("[SoloShop] Couldn't load the shop layout");
			return null;
		}

		m_SoloPlayerName = TextWidget.Cast(layoutRoot.FindAnyWidget("PlayerName"));
		m_SoloBalance = TextWidget.Cast(layoutRoot.FindAnyWidget("Balance"));
		m_SoloStatus = TextWidget.Cast(layoutRoot.FindAnyWidget("Status"));
		m_SoloItemName = TextWidget.Cast(layoutRoot.FindAnyWidget("ItemName"));
		m_SoloOwned = TextWidget.Cast(layoutRoot.FindAnyWidget("Owned"));
		m_SoloSearch = EditBoxWidget.Cast(layoutRoot.FindAnyWidget("Search"));
		m_SoloCategoryName = TextWidget.Cast(layoutRoot.FindAnyWidget("CategoryName"));
		m_SoloCategoryPrev = ButtonWidget.Cast(layoutRoot.FindAnyWidget("CategoryPrev"));
		m_SoloCategoryNext = ButtonWidget.Cast(layoutRoot.FindAnyWidget("CategoryNext"));
		m_SoloPageText = TextWidget.Cast(layoutRoot.FindAnyWidget("PageText"));
		m_SoloPagePrev = ButtonWidget.Cast(layoutRoot.FindAnyWidget("PagePrev"));
		m_SoloPageNext = ButtonWidget.Cast(layoutRoot.FindAnyWidget("PageNext"));
		m_SoloQuantity = TextWidget.Cast(layoutRoot.FindAnyWidget("Quantity"));
		m_SoloMinus = ButtonWidget.Cast(layoutRoot.FindAnyWidget("Minus"));
		m_SoloPlus = ButtonWidget.Cast(layoutRoot.FindAnyWidget("Plus"));
		m_SoloBuy = ButtonWidget.Cast(layoutRoot.FindAnyWidget("Buy"));
		m_SoloCashOut = ButtonWidget.Cast(layoutRoot.FindAnyWidget("CashOut"));
		m_SoloPayIn = ButtonWidget.Cast(layoutRoot.FindAnyWidget("PayIn"));
		m_SoloCashAmount = EditBoxWidget.Cast(layoutRoot.FindAnyWidget("CashAmount"));
		m_SoloSell = ButtonWidget.Cast(layoutRoot.FindAnyWidget("Sell"));
		m_SoloClose = ButtonWidget.Cast(layoutRoot.FindAnyWidget("Close"));
		m_SoloNavMarket = ButtonWidget.Cast(layoutRoot.FindAnyWidget("NavMarket"));
		m_SoloNavInventory = ButtonWidget.Cast(layoutRoot.FindAnyWidget("NavInventory"));
		m_SoloNavVehicles = ButtonWidget.Cast(layoutRoot.FindAnyWidget("NavVehicles"));
		m_SoloBuyBack = layoutRoot.FindAnyWidget("BuyBack");
		m_SoloBuyLabel = TextWidget.Cast(layoutRoot.FindAnyWidget("BuyLabel"));
		m_SoloSellLabel = TextWidget.Cast(layoutRoot.FindAnyWidget("SellLabel"));
		m_SoloNavMarketBack = layoutRoot.FindAnyWidget("NavMarketBack");
		m_SoloNavInventoryBack = layoutRoot.FindAnyWidget("NavInventoryBack");
		m_SoloNavVehiclesBack = layoutRoot.FindAnyWidget("NavVehiclesBack");
		m_SoloPreview = ItemPreviewWidget.Cast(layoutRoot.FindAnyWidget("Preview"));

		for (int i = 0; i < SOLO_SHOP_CARDS; i++)
		{
			string prefix = "Card" + i.ToString();
			m_SoloCards.Insert(layoutRoot.FindAnyWidget(prefix));
			m_SoloCardOwned.Insert(layoutRoot.FindAnyWidget(prefix + "Owned"));
			m_SoloCardPreviews.Insert(ItemPreviewWidget.Cast(layoutRoot.FindAnyWidget(prefix + "Preview")));
			m_SoloCardNames.Insert(TextWidget.Cast(layoutRoot.FindAnyWidget(prefix + "Name")));
			m_SoloCardPrices.Insert(TextWidget.Cast(layoutRoot.FindAnyWidget(prefix + "Price")));
			m_SoloCardButtons.Insert(ButtonWidget.Cast(layoutRoot.FindAnyWidget(prefix + "Button")));
		}
		SoloSizeText();
		return layoutRoot;
	}

	protected void SoloSizeText()
	{
		SoloProportion(TextWidget.Cast(layoutRoot.FindAnyWidget("PlayerName")), 0.8);
		SoloProportion(TextWidget.Cast(layoutRoot.FindAnyWidget("TraderName")), 0.75);
		SoloProportion(m_SoloBalance, 0.8);
		SoloProportion(TextWidget.Cast(layoutRoot.FindAnyWidget("SearchHint")), 0.75);
		SoloProportion(m_SoloItemName, 0.42);
		SoloProportion(m_SoloOwned, 0.75);
		SoloProportion(TextWidget.Cast(layoutRoot.FindAnyWidget("QuantityLabel")), 0.75);
		SoloProportion(m_SoloStatus, 0.28);
		foreach (TextWidget cardName : m_SoloCardNames)
			SoloProportion(cardName, 0.42);
		foreach (TextWidget cardPrice : m_SoloCardPrices)
			SoloProportion(cardPrice, 0.8);

		m_SoloCentered = new array<TextWidget>;
		SoloCenter("NavMarketLabel", 0.3);
		SoloCenter("NavInventoryLabel", 0.3);
		SoloCenter("NavVehiclesLabel", 0.3);
		SoloCenter("CloseLabel", 0.6);
		SoloCenter("CategoryPrevLabel", 0.6);
		SoloCenter("CategoryNextLabel", 0.6);
		SoloCenter("CategoryName", 0.55);
		SoloCenter("PagePrevLabel", 0.55);
		SoloCenter("PageNextLabel", 0.55);
		SoloCenter("PageText", 0.5);
		SoloCenter("DetailTitle", 0.5);
		SoloCenter("MinusLabel", 0.55);
		SoloCenter("PlusLabel", 0.55);
		SoloCenter("Quantity", 0.5);
		SoloCenter("BuyLabel", 0.38);
		SoloCenter("SellLabel", 0.38);
		SoloCenter("CashOutLabel", 0.45);
		SoloCenter("PayInLabel", 0.45);
		SoloProportion(TextWidget.Cast(layoutRoot.FindAnyWidget("CashHint")), 0.7);
	}

	protected void SoloCenter(string widgetName, float proportion)
	{
		TextWidget centered = TextWidget.Cast(layoutRoot.FindAnyWidget(widgetName));
		if (!centered)
			return;
		centered.SetTextProportion(proportion);
		m_SoloCentered.Insert(centered);
	}

	// Text widgets have no centring option, so each label is offset by half its spare space every frame.
	protected void SoloCenterLabels()
	{
		foreach (TextWidget centered : m_SoloCentered)
		{
			if (!centered.IsVisible())
				continue;
			float boxWidth, boxHeight;
			centered.GetScreenSize(boxWidth, boxHeight);
			int textWidth, textHeight;
			centered.Update();
			centered.GetTextSize(textWidth, textHeight);
			int offsetX = Math.Round((boxWidth - textWidth) / 2);
			int offsetY = Math.Round((boxHeight - textHeight) / 2);
			if (offsetX < 0)
				offsetX = 0;
			if (offsetY < 0)
				offsetY = 0;
			centered.SetTextOffset(offsetX, offsetY);
		}
	}

	protected void SoloShowButton(string buttonName, bool visible)
	{
		array<string> parts = {"", "Back", "Label"};
		foreach (string part : parts)
		{
			Widget piece = layoutRoot.FindAnyWidget(buttonName + part);
			if (piece)
				piece.Show(visible);
		}
	}

	protected void SoloProportion(TextWidget widget, float proportion)
	{
		if (widget)
			widget.SetTextProportion(proportion);
	}

	override void OnShow()
	{
		super.OnShow();
		GetGame().GetMission().PlayerControlDisable(INPUT_EXCLUDE_ALL);
		GetGame().GetUIManager().ShowUICursor(true);
		GetGame().GetInput().ChangeGameFocus(1);

		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		if (player && player.GetIdentity() && m_SoloPlayerName)
			m_SoloPlayerName.SetText(player.GetIdentity().GetName());

		SoloShopClientState.Message = "";
		m_SoloSeenStatus = -1;
		bool cash = SoloShopClientState.CashEnabled;
		SoloShowButton("CashOut", cash);
		SoloShowButton("PayIn", cash);
		Widget cashField = layoutRoot.FindAnyWidget("CashAmountBack");
		if (cashField)
			cashField.Show(cash);
		Widget cashHint = layoutRoot.FindAnyWidget("CashHint");
		if (cashHint)
			cashHint.Show(cash);
		SoloSetInventoryMode(m_SoloInventoryMode);
		SoloSendRequest(SOLO_SHOP_RPC_REQUEST_CATEGORIES, "");
		SoloSendRequest(SOLO_SHOP_RPC_REQUEST_SELLABLES, "");
	}

	override void OnHide()
	{
		super.OnHide();
		SoloClearPreviews();
		GetGame().GetMission().PlayerControlEnable(false);
		GetGame().GetUIManager().ShowUICursor(false);
		GetGame().GetInput().ResetGameFocus();
	}

	override void Update(float timeslice)
	{
		super.Update(timeslice);
		if (!layoutRoot)
			return;
		SoloCenterLabels();

		if (GetGame().GetInput().LocalPress("UAUIBack", false))
		{
			Close();
			return;
		}

		if (m_SoloSeenStatus != SoloShopClientState.StatusVersion)
		{
			m_SoloSeenStatus = SoloShopClientState.StatusVersion;
			SoloRefreshStatus();
			if (m_SoloAwaitingResult)
			{
				m_SoloAwaitingResult = false;
				SoloSendRequest(SOLO_SHOP_RPC_REQUEST_SELLABLES, "");
			}
		}
		if (m_SoloSeenCategories != SoloShopClientState.CategoriesVersion)
		{
			m_SoloSeenCategories = SoloShopClientState.CategoriesVersion;
			SoloOnCategoriesArrived();
		}
		if (m_SoloSeenItems != SoloShopClientState.ItemsVersion)
		{
			m_SoloSeenItems = SoloShopClientState.ItemsVersion;
			if (!m_SoloInventoryMode)
				SoloRebuild(true);
		}
		if (m_SoloSeenSell != SoloShopClientState.SellVersion)
		{
			m_SoloSeenSell = SoloShopClientState.SellVersion;
			SoloRebuild(false);
		}

		string search = m_SoloSearch.GetText();
		if (search != m_SoloSearchText)
		{
			m_SoloSearchText = search;
			SoloRebuild(true);
		}
	}

	override bool OnClick(Widget w, int x, int y, int button)
	{
		for (int i = 0; i < SOLO_SHOP_CARDS; i++)
		{
			if (w == m_SoloCardButtons[i])
			{
				SoloSelect(m_SoloPage * SOLO_SHOP_CARDS + i);
				return true;
			}
		}

		if (w == m_SoloClose)
			Close();
		else if (w == m_SoloNavMarket)
			SoloSetInventoryMode(false);
		else if (w == m_SoloNavInventory)
			SoloSetInventoryMode(true);
		else if (w == m_SoloNavVehicles)
			SoloJumpToCategory(SoloShopClientState.VehicleCategory);
		else if (w == m_SoloCategoryPrev)
			SoloStepCategory(-1);
		else if (w == m_SoloCategoryNext)
			SoloStepCategory(1);
		else if (w == m_SoloPagePrev)
			SoloStepPage(-1);
		else if (w == m_SoloPageNext)
			SoloStepPage(1);
		else if (w == m_SoloMinus)
			SoloStepAmount(-1);
		else if (w == m_SoloPlus)
			SoloStepAmount(1);
		else if (w == m_SoloBuy)
			SoloBuySelected();
		else if (w == m_SoloCashOut)
			SoloCashOut();
		else if (w == m_SoloPayIn)
			SoloPayIn();
		else if (w == m_SoloSell)
			SoloSellSelected();
		else
			return super.OnClick(w, x, y, button);
		return true;
	}

	protected void SoloSendRequest(int rpcType, string value)
	{
		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		if (player)
			GetGame().RPCSingleParam(player, rpcType, new Param1<string>(value), true);
	}

	protected void SoloRefreshStatus()
	{
		m_SoloBalance.SetText("MONEY: " + SoloShopText.Money(SoloShopClientState.Balance));
		m_SoloStatus.SetText(SoloShopClientState.Message);
		if (SoloShopClientState.MessageOk)
			m_SoloStatus.SetColor(ARGB(255, 140, 220, 120));
		else
			m_SoloStatus.SetColor(ARGB(255, 240, 130, 110));
	}

	protected void SoloSetInventoryMode(bool inventoryMode)
	{
		m_SoloInventoryMode = inventoryMode;
		SoloPaintNav();
		if (inventoryMode)
			m_SoloCategoryName.SetText("YOUR INVENTORY");
		else if (SoloShopClientState.Categories.Count() > 0)
			m_SoloCategoryName.SetText(SoloShopClientState.Categories[m_SoloCategoryIndex]);
		SoloShowButton("CategoryPrev", !inventoryMode);
		SoloShowButton("CategoryNext", !inventoryMode);
		if (inventoryMode)
			SoloSendRequest(SOLO_SHOP_RPC_REQUEST_SELLABLES, "");
		SoloRebuild(true);
	}

	protected void SoloPaintNav()
	{
		int active = ARGB(255, 72, 158, 77);
		int idle = ARGB(255, 31, 33, 33);
		bool onVehicles = !m_SoloInventoryMode && SoloShopClientState.VehicleCategory != "" && m_SoloLastCategory == SoloShopClientState.VehicleCategory;
		if (m_SoloNavMarketBack)
		{
			if (!m_SoloInventoryMode && !onVehicles)
				m_SoloNavMarketBack.SetColor(active);
			else
				m_SoloNavMarketBack.SetColor(idle);
		}
		if (m_SoloNavInventoryBack)
		{
			if (m_SoloInventoryMode)
				m_SoloNavInventoryBack.SetColor(active);
			else
				m_SoloNavInventoryBack.SetColor(idle);
		}
		if (m_SoloNavVehiclesBack)
		{
			if (onVehicles)
				m_SoloNavVehiclesBack.SetColor(active);
			else
				m_SoloNavVehiclesBack.SetColor(idle);
		}
	}

	protected void SoloOnCategoriesArrived()
	{
		int count = SoloShopClientState.Categories.Count();
		if (count == 0)
		{
			m_SoloCategoryName.SetText("NOTHING FOR SALE");
			return;
		}
		int remembered = SoloShopClientState.Categories.Find(m_SoloLastCategory);
		if (remembered < 0)
			remembered = 0;
		SoloShowCategory(remembered);
	}

	protected void SoloShowCategory(int index)
	{
		int count = SoloShopClientState.Categories.Count();
		if (count == 0)
			return;
		m_SoloCategoryIndex = (index + count) % count;
		m_SoloLastCategory = SoloShopClientState.Categories[m_SoloCategoryIndex];
		m_SoloInventoryMode = false;
		m_SoloCategoryName.SetText(m_SoloLastCategory);
		SoloShowButton("CategoryPrev", true);
		SoloShowButton("CategoryNext", true);
		SoloPaintNav();
		SoloSendRequest(SOLO_SHOP_RPC_REQUEST_ITEMS, m_SoloLastCategory);
	}

	protected void SoloStepCategory(int step)
	{
		SoloShowCategory(m_SoloCategoryIndex + step);
	}

	protected void SoloJumpToCategory(string categoryName)
	{
		int index = -1;
		if (categoryName != "")
			index = SoloShopClientState.Categories.Find(categoryName);
		if (index < 0)
		{
			m_SoloStatus.SetText("The trader has no vehicles for sale.");
			return;
		}
		SoloShowCategory(index);
	}

	protected int SoloSourceCount()
	{
		if (m_SoloInventoryMode)
			return SoloShopClientState.SellClasses.Count();
		return SoloShopClientState.ItemClasses.Count();
	}

	protected string SoloSourceClass(int sourceIndex)
	{
		if (m_SoloInventoryMode)
			return SoloShopClientState.SellClasses[sourceIndex];
		return SoloShopClientState.ItemClasses[sourceIndex];
	}

	protected int SoloOwnedCount(string className)
	{
		int index = SoloShopClientState.SellClasses.Find(className);
		if (index < 0)
			return 0;
		return SoloShopClientState.SellCounts[index];
	}

	protected int SoloSellPrice(string className)
	{
		int index = SoloShopClientState.SellClasses.Find(className);
		if (index >= 0)
			return SoloShopClientState.SellPrices[index];
		if (!m_SoloInventoryMode && m_SoloSelected >= 0 && m_SoloSelected < m_SoloFiltered.Count())
			return SoloShopClientState.ItemSell[m_SoloFiltered[m_SoloSelected]];
		return 0;
	}

	protected void SoloRebuild(bool resetPage)
	{
		string selectedClass = SoloSelectedClass();
		m_SoloFiltered.Clear();
		string filter = m_SoloSearchText;
		filter.ToLower();
		for (int i = 0; i < SoloSourceCount(); i++)
		{
			string lowered = SoloShopText.DisplayName(SoloSourceClass(i));
			lowered.ToLower();
			if (filter == "" || lowered.Contains(filter))
				m_SoloFiltered.Insert(i);
		}

		m_SoloSelected = -1;
		for (int j = 0; j < m_SoloFiltered.Count(); j++)
		{
			if (SoloSourceClass(m_SoloFiltered[j]) == selectedClass)
				m_SoloSelected = j;
		}
		if (resetPage)
			m_SoloPage = 0;
		int pages = SoloPageCount();
		if (m_SoloPage >= pages)
			m_SoloPage = pages - 1;
		if (m_SoloSelected < 0 && m_SoloFiltered.Count() > 0)
			m_SoloSelected = m_SoloPage * SOLO_SHOP_CARDS;
		if (m_SoloSelected >= m_SoloFiltered.Count())
			m_SoloSelected = m_SoloFiltered.Count() - 1;

		SoloFillGrid();
		SoloShowDetails();
	}

	protected string SoloSelectedClass()
	{
		if (m_SoloSelected < 0 || m_SoloSelected >= m_SoloFiltered.Count())
			return "";
		return SoloSourceClass(m_SoloFiltered[m_SoloSelected]);
	}

	protected int SoloPageCount()
	{
		int pages = (m_SoloFiltered.Count() + SOLO_SHOP_CARDS - 1) / SOLO_SHOP_CARDS;
		if (pages < 1)
			pages = 1;
		return pages;
	}

	protected void SoloStepPage(int step)
	{
		int pages = SoloPageCount();
		m_SoloPage = (m_SoloPage + step + pages) % pages;
		m_SoloSelected = m_SoloPage * SOLO_SHOP_CARDS;
		if (m_SoloSelected >= m_SoloFiltered.Count())
			m_SoloSelected = m_SoloFiltered.Count() - 1;
		SoloFillGrid();
		SoloShowDetails();
	}

	protected void SoloFillGrid()
	{
		SoloClearCardPreviews();
		int pageNumber = m_SoloPage + 1;
		int pageTotal = SoloPageCount();
		m_SoloPageText.SetText(pageNumber.ToString() + " / " + pageTotal.ToString());

		for (int i = 0; i < SOLO_SHOP_CARDS; i++)
		{
			int filteredIndex = m_SoloPage * SOLO_SHOP_CARDS + i;
			Widget cardWidget = m_SoloCards[i];
			if (!cardWidget)
				continue;
			if (filteredIndex >= m_SoloFiltered.Count())
			{
				cardWidget.Show(false);
				continue;
			}
			cardWidget.Show(true);

			int sourceIndex = m_SoloFiltered[filteredIndex];
			string className = SoloSourceClass(sourceIndex);
			int ownedCount = SoloOwnedCount(className);
			m_SoloCardNames[i].SetText(SoloShopText.DisplayName(className));
			if (m_SoloInventoryMode)
				m_SoloCardPrices[i].SetText("x" + ownedCount.ToString() + "   " + SoloShopText.Money(SoloShopClientState.SellPrices[sourceIndex]));
			else if (SoloShopClientState.ItemBuy[sourceIndex] <= 0)
				m_SoloCardPrices[i].SetText("SELL ONLY");
			else
				m_SoloCardPrices[i].SetText(SoloShopText.Money(SoloShopClientState.ItemBuy[sourceIndex]));
			if (m_SoloCardOwned[i])
				m_SoloCardOwned[i].Show(ownedCount > 0);
			m_SoloCardItems.Insert(SoloAttachPreview(m_SoloCardPreviews[i], className));
		}
		SoloPaintSelection();
	}

	protected void SoloPaintSelection()
	{
		for (int i = 0; i < SOLO_SHOP_CARDS; i++)
		{
			if (!m_SoloCards[i])
				continue;
			if (m_SoloPage * SOLO_SHOP_CARDS + i == m_SoloSelected)
				m_SoloCards[i].SetColor(ARGB(255, 72, 158, 77));
			else
				m_SoloCards[i].SetColor(ARGB(255, 41, 43, 43));
		}
	}

	protected void SoloSelect(int filteredIndex)
	{
		if (filteredIndex < 0 || filteredIndex >= m_SoloFiltered.Count())
			return;
		m_SoloSelected = filteredIndex;
		m_SoloAmount = 1;
		SoloPaintSelection();
		SoloShowDetails();
	}

	protected void SoloStepAmount(int step)
	{
		m_SoloAmount = m_SoloAmount + step;
		if (m_SoloAmount < 1)
			m_SoloAmount = 1;
		if (m_SoloAmount > SOLO_SHOP_MAX_AMOUNT)
			m_SoloAmount = SOLO_SHOP_MAX_AMOUNT;
		SoloShowDetails();
	}

	protected void SoloShowDetails()
	{
		string className = SoloSelectedClass();
		if (m_SoloPreviewItem)
			GetGame().ObjectDelete(m_SoloPreviewItem);
		m_SoloPreviewItem = null;

		if (className == "")
		{
			m_SoloItemName.SetText("Pick an item");
			m_SoloOwned.SetText("");
			m_SoloQuantity.SetText("1");
			m_SoloBuyLabel.SetText("BUY");
			m_SoloSellLabel.SetText("SELL");
			if (m_SoloPreview)
				m_SoloPreview.SetItem(null);
			return;
		}

		int ownedCount = SoloOwnedCount(className);
		m_SoloItemName.SetText(SoloShopText.DisplayName(className));
		m_SoloOwned.SetText("In your inventory: " + ownedCount.ToString());
		m_SoloQuantity.SetText(m_SoloAmount.ToString());
		m_SoloPreviewItem = SoloAttachPreview(m_SoloPreview, className);

		int unitPrice = 0;
		if (!m_SoloInventoryMode)
			unitPrice = SoloShopClientState.ItemBuy[m_SoloFiltered[m_SoloSelected]];
		bool canBuy = unitPrice > 0;
		SoloShowButton("Buy", canBuy);
		if (canBuy)
			m_SoloBuyLabel.SetText("BUY - " + SoloShopText.Money(unitPrice * m_SoloAmount));
		m_SoloSellLabel.SetText("SELL - " + SoloShopText.Money(SoloSellPrice(className)));
	}

	protected EntityAI SoloAttachPreview(ItemPreviewWidget widget, string className)
	{
		if (!widget)
			return null;
		widget.SetItem(null);
		if (className == "" || GetGame().IsKindOf(className, "CarScript") || GetGame().IsKindOf(className, "BoatScript"))
			return null;
		EntityAI previewItem = EntityAI.Cast(GetGame().CreateObjectEx(className, "0 0 0", ECE_LOCAL));
		if (previewItem)
			widget.SetItem(previewItem);
		return previewItem;
	}

	protected void SoloClearCardPreviews()
	{
		foreach (ItemPreviewWidget cardPreview : m_SoloCardPreviews)
		{
			if (cardPreview)
				cardPreview.SetItem(null);
		}
		foreach (EntityAI cardItem : m_SoloCardItems)
		{
			if (cardItem)
				GetGame().ObjectDelete(cardItem);
		}
		m_SoloCardItems.Clear();
	}

	protected void SoloClearPreviews()
	{
		SoloClearCardPreviews();
		if (m_SoloPreview)
			m_SoloPreview.SetItem(null);
		if (m_SoloPreviewItem)
			GetGame().ObjectDelete(m_SoloPreviewItem);
		m_SoloPreviewItem = null;
	}

	protected void SoloBuySelected()
	{
		string className = SoloSelectedClass();
		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		if (className == "" || !player || m_SoloInventoryMode)
			return;
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_BUY, new Param2<string, int>(className, m_SoloAmount), true);
		SoloShowPending();
	}

	protected void SoloCashOut()
	{
		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		if (!player || !m_SoloCashAmount)
			return;
		string typed = m_SoloCashAmount.GetText();
		typed.Replace(",", "");
		typed.Replace("$", "");
		typed = typed.Trim();
		int amount = typed.ToInt();
		if (amount <= 0)
		{
			m_SoloStatus.SetColor(ARGB(255, 240, 130, 110));
			m_SoloStatus.SetText("Type how much cash you want, then press CASH OUT.");
			return;
		}
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_CASH_OUT, new Param1<int>(amount), true);
		SoloShowPending();
	}

	protected void SoloPayIn()
	{
		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		if (!player)
			return;
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_PAY_IN, new Param1<int>(0), true);
		SoloShowPending();
	}

	protected void SoloSellSelected()
	{
		string className = SoloSelectedClass();
		PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
		if (className == "" || !player)
			return;
		if (SoloOwnedCount(className) <= 0)
		{
			m_SoloStatus.SetColor(ARGB(255, 240, 130, 110));
			m_SoloStatus.SetText("You don't have one to sell (empty it and take its attachments off first).");
			return;
		}
		GetGame().RPCSingleParam(player, SOLO_SHOP_RPC_SELL, new Param1<string>(className), true);
		SoloShowPending();
	}

	protected void SoloShowPending()
	{
		m_SoloAwaitingResult = true;
		m_SoloStatus.SetColor(ARGB(255, 200, 200, 200));
		m_SoloStatus.SetText("Talking to the trader...");
	}
}
