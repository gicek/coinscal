// Number formatting, matching the app's PriceFormatter: always "," grouping and "." decimals whatever the
// language, so the demo panel shows exactly what the app shows.

function fractionDigits(price) {
    if (price < 1) return [4, 6];
    if (price < 100) return [2, 2];
    return [0, 0];
}

/** A popover price: grouped number without a currency symbol (the currency is implied). */
export function formatPrice(price) {
    const [min, max] = fractionDigits(price);
    return new Intl.NumberFormat("en-US", { minimumFractionDigits: min, maximumFractionDigits: max }).format(price);
}

/** A menu bar price: like formatPrice, but without trailing zeros. */
export function formatShort(price) {
    const max = price < 1 ? 4 : price < 100 ? 2 : 0;
    return new Intl.NumberFormat("en-US", { minimumFractionDigits: 0, maximumFractionDigits: max }).format(price);
}

export function formatPercent(percent) {
    return `${percent >= 0 ? "+" : ""}${percent.toFixed(2)}%`;
}
