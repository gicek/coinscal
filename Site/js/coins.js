// The coins the demo offers: the app's recommended coins (Apple/Mac/Resources/recommendedCoins.json), with names
// and ids from its catalog. Logos are local copies in img/coins/<id>.png.
export const COINS = [
    { id: "bitcoin", symbol: "BTC", name: "Bitcoin" },
    { id: "ethereum", symbol: "ETH", name: "Ethereum" },
    { id: "binancecoin", symbol: "BNB", name: "BNB" },
    { id: "solana", symbol: "SOL", name: "Solana" },
    { id: "ripple", symbol: "XRP", name: "XRP" },
    { id: "cardano", symbol: "ADA", name: "Cardano" },
    { id: "dogecoin", symbol: "DOGE", name: "Dogecoin" },
    { id: "avalanche-2", symbol: "AVAX", name: "Avalanche" },
    { id: "polkadot", symbol: "DOT", name: "Polkadot" },
    { id: "polygon-ecosystem-token", symbol: "POL", name: "POL (ex-MATIC)" },
];

export const coinById = (id) => COINS.find((c) => c.id === id);

// The app's quote currencies (BaseCurrency), in its order, with its symbols.
export const CURRENCIES = [
    ["USD", "$"], ["CNY", "¥"], ["KRW", "₩"], ["HKD", "HK$"], ["JPY", "¥"], ["TWD", "NT$"],
    ["SGD", "$"], ["MYR", "RM"], ["AUD", "$"], ["CAD", "$"], ["EUR", "€"], ["GBP", "£"],
];

// Constants.Defaults.upColorHex / downColorHex.
export const UP_COLOR = "#2CBD84";
export const DOWN_COLOR = "#F6465D";
