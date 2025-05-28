/**
 * Service for syncing and managing products with an external API.
 */
public with sharing class ProductService {
    // Config
    private static final String API_ENDPOINT = ProductAPIConfigService.getEndpoint();
    private static final Integer BATCH_SIZE = 50;
    private static final Decimal MAX_TOTAL_PRICE = 10000;
    private static final Integer MAX_PRODUCTS = 100;
    
    /**
     * Maps external API product data.
     */
    public class ExternalProductWrapper {
        @AuraEnabled public Integer id;
        @AuraEnabled public String title;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Decimal discountPercentage;
        @AuraEnabled public Decimal rating;
        @AuraEnabled public Integer stock;
        @AuraEnabled public String brand;
        @AuraEnabled public String category;
        @AuraEnabled public String thumbnail;
        @AuraEnabled public List<String> images;
        @AuraEnabled public List<String> tags;
    }
    
    /**
     * Maps external API response.
     */
    public class ExternalProductResponse {
        @AuraEnabled public List<ExternalProductWrapper> products;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer skip;
        @AuraEnabled public Integer limitValue;
    }
    
    /**
     * Wrapper for Product2 data for UI.
     */
    public class ProductDisplayWrapper {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Description;
        @AuraEnabled public String Family;
        @AuraEnabled public String Brand;
        @AuraEnabled public String ProductCode;
        @AuraEnabled public Boolean IsActive;
        @AuraEnabled public Datetime CreatedDate;
        @AuraEnabled public String DisplayUrl;
        @AuraEnabled public Decimal Stock;
        @AuraEnabled public String Images;
        @AuraEnabled public String Tags;
        @AuraEnabled public Decimal Rating;
        @AuraEnabled public Decimal DiscountPercentage;
        @AuraEnabled public Decimal UnitPrice;
        
        /**
         * Default constructor
         */
        public ProductDisplayWrapper() {}
        
        /**
         * Constructor that creates a wrapper from a Product2 record.
         */
        public ProductDisplayWrapper(Product2 product) {
            this.Id = product.Id;
            this.Name = product.Name;
            this.Description = product.Description;
            this.Family = product.Family;
            this.Brand = product.Brand__c;
            this.ProductCode = product.ProductCode;
            this.IsActive = product.IsActive;
            this.CreatedDate = product.CreatedDate;
            this.DisplayUrl = product.DisplayUrl;
            this.Stock = product.Stock__c;
            this.Images = product.Images__c;
            this.Tags = product.Tags__c;
            this.Rating = product.Rating__c;
            this.DiscountPercentage = product.DiscountPercentage__c;
            this.UnitPrice = product.PricebookEntries?.isEmpty() ? 0 : product.PricebookEntries[0].UnitPrice;
        }
    }
    
    /**
     * Sync products from API to Salesforce.
     */
    @AuraEnabled
    public static String syncProducts() {
        try {
            Http http = new Http();
            HttpRequest request = createRequest('/products?limit=0');
            request.setTimeout(120000);
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                ExternalProductResponse productResponse = (ExternalProductResponse)JSON.deserialize(response.getBody(), ExternalProductResponse.class);
                
                if (productResponse.products != null && !productResponse.products.isEmpty()) {
                    return processProductsResponse(productResponse);
                }
            }
            return 'No products to sync';
        } catch(Exception e) {
            throw new AuraHandledException('Error syncing products: ' + e.getMessage());
        }
    }
    
    /**
     * Returns true if no products exist.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean needsSync() {
        try {
            Integer totalProducts = [SELECT COUNT() FROM Product2];
            return totalProducts == 0;
        } catch(Exception e) {
            throw new AuraHandledException('Error checking sync status: ' + e.getMessage());
        }
    }
    
    /**
     * Get all active products for UI.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductDisplayWrapper> getProducts() {
        try {
            List<Product2> products = [
                SELECT Id, Name, Description, Family, Brand__c, ProductCode, IsActive, CreatedDate, DisplayUrl, Stock__c, Images__c, Tags__c, Rating__c, DiscountPercentage__c,
                    (SELECT UnitPrice FROM PricebookEntries WHERE IsActive = true LIMIT 1)
                FROM Product2
                WHERE IsActive = true
                ORDER BY Family ASC, Name ASC
            ];
            return createProductWrappers(products);
        } catch(Exception e) {
            throw new AuraHandledException('Error retrieving products: ' + e.getMessage());
        }
    }
    
    /**
     * Delete all products.
     */
    @AuraEnabled
    public static void deleteAllProducts() {
        try {
            List<Product2> products = [SELECT Id FROM Product2];
            if (!products.isEmpty()) {
                delete products;
            }
        } catch(Exception e) {
            throw new AuraHandledException('Error deleting products: ' + e.getMessage());
        }
    }
    
    /**
     * Insert new products and pricebook entries from API response.
     */
    private static String processProductsResponse(ExternalProductResponse productResponse) {
        if (productResponse?.products == null || productResponse.products.isEmpty()) {
            return 'No products to sync';
        }
        
        Id stdPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
        Integer totalProducts = productResponse.products.size();
        List<SObject> allRecords = new List<SObject>();
        
        // Get existing product codes to avoid duplicates
        Set<String> existingProductCodes = new Set<String>();
        for(Product2 p : [SELECT ProductCode FROM Product2 WHERE ProductCode LIKE 'PROD-%']) {
            existingProductCodes.add(p.ProductCode);
        }
        
        for(Integer i = 0; i < totalProducts; i += BATCH_SIZE) {
            Integer endIndex = Math.min(i + BATCH_SIZE, totalProducts);
            
            for(Integer j = i; j < endIndex; j++) {
                ExternalProductWrapper pw = productResponse.products[j];
                String productCode = 'PROD-' + pw.id;
                
                // Skip if product already exists
                if(existingProductCodes.contains(productCode)) {
                    continue;
                }
                
                Product2 product = new Product2(
                    Name = pw.title,
                    Description = pw.description,
                    Family = pw.category,
                    Brand__c = pw.brand,
                    ProductCode = productCode,
                    IsActive = true,
                    DisplayUrl = pw.thumbnail,
                    Stock__c = pw.stock,
                    Images__c = String.join(pw.images, ','),
                    Tags__c = String.join(pw.tags, ','),
                    Rating__c = pw.rating,
                    DiscountPercentage__c = pw.discountPercentage
                );
                allRecords.add(product);
            }
        }
        
        if (!allRecords.isEmpty()) {
            try {
                 // Insert all products in a single DML operation
                Database.SaveResult[] results = Database.insert(allRecords, false);
                
                // Log results
                Integer successCount = 0;
                Integer failureCount = 0;
                for(Database.SaveResult sr : results) {
                    if(sr.isSuccess()) {
                        successCount++;
                    } else {
                        failureCount++;
                    }
                }
                
                // Create pricebook entries for successful inserts
                List<PricebookEntry> entries = new List<PricebookEntry>();
                for (Integer k = 0; k < results.size(); k++) {
                    if (results[k].isSuccess()) {
                        ExternalProductWrapper pw = productResponse.products[k];
                        entries.add(new PricebookEntry(
                            Pricebook2Id = stdPricebookId,
                            Product2Id = results[k].getId(),
                            UnitPrice = pw.price,
                            IsActive = true
                        ));
                    }
                }
                if (!entries.isEmpty()) {
                    try {
                        Database.SaveResult[] pbeResults = Database.insert(entries, false);
                        // Log results
                        successCount = 0;
                        failureCount = 0;
                        for(Database.SaveResult sr : pbeResults) {
                            if(sr.isSuccess()) {
                                successCount++;
                            } else {
                                failureCount++;
                            }
                        }
                    } catch(Exception e) {
                        throw e;
                    }
                }
            } catch(Exception e) {
                throw e;
            }
        }
        
        return 'Successfully synced ' + productResponse.products.size() + ' products';
    }
    
    /**
     * Wraps Product2 records for UI, applies limits.
     */
    private static List<ProductDisplayWrapper> createProductWrappers(List<Product2> products) {
        Map<String, List<Product2>> categoryMap = new Map<String, List<Product2>>();
        for (Product2 product : products) {
            if (!categoryMap.containsKey(product.Family)) {
                categoryMap.put(product.Family, new List<Product2>());
            }
            categoryMap.get(product.Family).add(product);
        }
        
        List<ProductDisplayWrapper> result = new List<ProductDisplayWrapper>();
        for (List<Product2> catProducts : categoryMap.values()) {
            Decimal sum = 0;
            Integer count = 0;
            
            for (Product2 product : catProducts) {
                Decimal price = product.PricebookEntries?.isEmpty() ? 0 : product.PricebookEntries[0].UnitPrice;
                if (price > MAX_TOTAL_PRICE) continue;
                if (count >= MAX_PRODUCTS || sum + price > MAX_TOTAL_PRICE) break;
                
                result.add(new ProductDisplayWrapper(product));
                sum += price;
                count++;
            }
        }
        
        return result;
    }
    
    /**
     * Creates an HTTP request for the API.
     */
    private static HttpRequest createRequest(String endpoint) {
        HttpRequest req = new HttpRequest();
        String fullEndpoint = endpoint.startsWith('/auth/') ?
            API_ENDPOINT + endpoint :
            API_ENDPOINT + '/auth' + endpoint;
        
        req.setEndpoint(fullEndpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        
        ProductAPIConfigService.addAuthHeader(req);
        
        return req;
    }
}