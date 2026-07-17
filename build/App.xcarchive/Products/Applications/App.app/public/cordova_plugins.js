
  cordova.define('cordova/plugin_list', function(require, exports, module) {
    module.exports = [
      {
          "id": "cordova-plugin-purchase-storekit2.CdvPurchaseStoreKit2",
          "file": "plugins/cordova-plugin-purchase-storekit2/www/storekit2-plugin.js",
          "pluginId": "cordova-plugin-purchase-storekit2",
        "clobbers": [
          "CdvPurchaseStoreKit2"
        ]
        },
      {
          "id": "cordova-plugin-purchase.CdvPurchase",
          "file": "plugins/cordova-plugin-purchase/www/store.js",
          "pluginId": "cordova-plugin-purchase",
        "clobbers": [
          "CdvPurchase",
          "store"
        ]
        }
    ];
    module.exports.metadata =
    // TOP OF METADATA
    {
      "cordova-plugin-purchase": "13.17.2",
      "cordova-plugin-purchase-storekit2": "1.0.5"
    };
    // BOTTOM OF METADATA
    });
    