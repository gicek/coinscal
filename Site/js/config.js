// The only place the site's outbound links and domain live. Pages reference them with data-link="<key>";
// an empty value disables the matching button instead of pointing it at "#".
export const SITE_URL = "https://coinscal.app/";

export const LINKS = {
    github: "https://github.com/gicek/coinscal",
    // The latest notarized DMG on the download domain (docs/UPDATES.md).
    download: "https://dl.coinscal.app/Coinscal.dmg",
    releases: "https://github.com/gicek/coinscal/releases",
    issues: "https://github.com/gicek/coinscal/issues",
    // ExchangeRate-API's open access terms ask for this link on pages that show its rates (the demo's currencies).
    exchangeRateApi: "https://www.exchangerate-api.com",
};
