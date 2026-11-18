// Number formatting, matching the app's PriceFormatter: always "," grouping and "." decimals whatever the
// language, so the demo panel shows exactly what the app shows.

function fractionDigits(price) {
    if (price < 1) return [4, 6];
    if (price < 100) return [2, 2];
    return [0, 0];
}

function decimalPrice(price, min, max) {
    if (price > 0 && price <= 10 ** -max / 2) return price.toExponential(2);
    return new Intl.NumberFormat("en-US", {
        minimumFractionDigits: min,
        maximumFractionDigits: max,
        roundingMode: "halfEven",
    }).format(price);
}

/** A popover price: grouped number without a currency symbol (the currency is implied). */
export function formatPrice(price) {
    const [min, max] = fractionDigits(price);
    return decimalPrice(price, min, max);
}

/** A menu bar price: like formatPrice, but without trailing zeros. */
export function formatShort(price) {
    const max = price < 1 ? 4 : price < 100 ? 2 : 0;
    return decimalPrice(price, 0, max);
}

export function formatPercent(percent) {
    return `${percent >= 0 ? "+" : ""}${percent.toFixed(2)}%`;
}
