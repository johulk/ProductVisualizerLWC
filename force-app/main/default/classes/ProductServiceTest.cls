    /**
     * Test class for ProductService
     * Tests product synchronization, retrieval, and management functionality
     *
     * @author Igor Braga
     * @version 1.0
     */
    @isTest
    private class ProductServiceTest {
        // Test configuration constants
        private static final String TEST_USERNAME = 'emilys';
        private static final String TEST_PASSWORD = 'emilyspass';
        
        // Mock class for HTTP callouts
        private class MockHttpCallout implements HttpCalloutMock {
            private List<HttpResponse> responses;
            private Integer callCount = 0;
            
            public MockHttpCallout(List<HttpResponse> responses) {
                this.responses = responses;
            }
            
            public HTTPResponse respond(HTTPRequest req) {
                if (callCount < responses.size()) {
                    HttpResponse res = responses[callCount];
                    callCount++;
                    return res;
                }
                HttpResponse res = new HttpResponse();
                res.setStatusCode(404);
                res.setBody('{"error":"Not Found"}');
                return res;
            }
        }
        
        /**
         * Test data setup
         * Creates test products and pricebook entries
         */
        @TestSetup
        static void setupTestData() {
            // Ensure standard pricebook exists and is active
            Id stdPricebookId = Test.getStandardPricebookId();
            Pricebook2 stdPb = new Pricebook2(Id = stdPricebookId, IsActive = true, Name = 'Standard Price Book');
            upsert stdPb;
            
            // Create test products
            List<Product2> products = new List<Product2>{
                new Product2(
                    Name = 'Test Product 1',
                Description = 'Test Description 1',
                Family = 'Test Category',
                Brand__c = 'Test Brand',
                ProductCode = 'PROD-1',
                IsActive = true,
                DisplayUrl = 'https://example.com/image1.jpg',
                Stock__c = 100,
                Images__c = 'https://example.com/image1.jpg',
                Tags__c = 'tag1,tag2',
                Rating__c = 4.5,
                DiscountPercentage__c = 10
                    )
            };
            insert products;
            
            // Create pricebook entries
            List<PricebookEntry> entries = new List<PricebookEntry>();
            for(Product2 product : products) {
                entries.add(new PricebookEntry(
                    Pricebook2Id = stdPricebookId,
                Product2Id = product.Id,
                UnitPrice = 100,
                IsActive = true
                    ));
            }
            insert entries;
        }
        
        /**
         * Tests syncProducts method
         */
        @isTest
        static void testSyncProducts() {
            // Test successful sync
            List<HttpResponse> successResponses = new List<HttpResponse>{
                createLoginResponse(),
                createProductsResponse()
            };
            Test.setMock(HttpCalloutMock.class, new MockHttpCallout(successResponses));
            
            Test.startTest();
            String result = ProductService.syncProducts();
            Test.stopTest();
            
            System.assert(result.contains('Successfully synced'), 'Should return success message');
        }
        
        /**
         * Tests syncProducts method with empty response
         */
        @isTest
        static void testSyncProductsEmpty() {
            List<HttpResponse> emptyResponses = new List<HttpResponse>{
                createLoginResponse(),
                createEmptyProductsResponse()
            };
            Test.setMock(HttpCalloutMock.class, new MockHttpCallout(emptyResponses));
            
            Test.startTest();
            String result = ProductService.syncProducts();
            Test.stopTest();
            
            System.assertEquals('No products to sync', result, 'Should return no products message');
        }
        
        /**
         * Tests syncProducts method with error
         */
        @isTest
        static void testSyncProductsError() {
            List<HttpResponse> errorResponses = new List<HttpResponse>{
                createErrorResponse()
            };
            Test.setMock(HttpCalloutMock.class, new MockHttpCallout(errorResponses));
            
            Test.startTest();
            try {
                ProductService.syncProducts();
                System.assert(false, 'Should have thrown an exception');
            } catch(AuraHandledException e) {
                System.assert(e.getMessage() != null, 'Should throw AuraHandledException');
            }
            Test.stopTest();
        }
        
        /**
         * Tests getProducts method
         */
        @isTest
        static void testGetProducts() {
            Test.startTest();
            List<ProductService.ProductDisplayWrapper> products = ProductService.getProducts();
            Test.stopTest();
            
            System.assertNotEquals(0, products.size(), 'Should return products');
            for(ProductService.ProductDisplayWrapper product : products) {
                System.assertNotEquals(null, product.Id, 'Product should have Id');
                System.assertNotEquals(null, product.Name, 'Product should have Name');
                System.assertNotEquals(null, product.UnitPrice, 'Product should have UnitPrice');
            }
        }
        
        /**
         * Tests needsSync method
         */
        @isTest
        static void testNeedsSync() {
            Test.startTest();
            Boolean needsSync = ProductService.needsSync();
            Test.stopTest();
            
            System.assertEquals(false, needsSync, 'Should not need sync with existing products');
        }
        
        /**
         * Tests deleteAllProducts method
         */
        @isTest
        static void testDeleteAllProducts() {
            Test.startTest();
            ProductService.deleteAllProducts();
            Test.stopTest();
            
            List<Product2> remainingProducts = [SELECT Id FROM Product2];
            System.assertEquals(0, remainingProducts.size(), 'All products should be deleted');
        }
        
        /**
         * Tests deleteAllProducts method with error
         */
        @isTest
        static void testDeleteAllProductsError() {
            // Create a product that will cause an error when deleted
            Product2 product = new Product2(
                Name = 'Test Product',
            ProductCode = 'TEST-1',
            IsActive = true
                );
            insert product;
            
            // Create a pricebook entry
            Id stdPricebookId = Test.getStandardPricebookId();
            PricebookEntry entry = new PricebookEntry(
                Pricebook2Id = stdPricebookId,
            Product2Id = product.Id,
            UnitPrice = 100,
            IsActive = true
                );
            insert entry;
            
            // Create an opportunity with the product to make it undeletable
            Opportunity opp = new Opportunity(
                Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today()
                );
            insert opp;
            
            OpportunityLineItem oli = new OpportunityLineItem(
                OpportunityId = opp.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1,
            UnitPrice = 100
                );
            insert oli;
            
            Test.startTest();
            try {
                ProductService.deleteAllProducts();
                System.assert(false, 'Should have thrown an exception');
            } catch(AuraHandledException e) {
                System.assert(e.getMessage() != null, 'Should throw AuraHandledException');
            }
            Test.stopTest();
        }
        
        /**
         * Tests processProductsResponse for partial Product2 insert failure
         */
        @isTest
        static void testProcessProductsResponsePartialFailure() {
            // Prepare a response with one valid and one invalid product
            List<HttpResponse> responses = new List<HttpResponse>();
            HttpResponse loginRes = createLoginResponse();
            responses.add(loginRes);
            
            // Use unique ProductCodes to avoid duplicates
            String body = '{"products":[' +
                '{"id":101,"title":"Valid Product","description":"desc","price":100,"discountPercentage":10,"rating":4.5,"stock":50,"brand":"Brand","category":"Cat","thumbnail":"url","images":["img"],"tags":["tag"]},' +
                '{"id":102,"title":"","description":"desc","price":100,"discountPercentage":10,"rating":4.5,"stock":50,"brand":"Brand","category":"Cat","thumbnail":"url","images":["img"],"tags":["tag"]}' +
                '],"total":2,"skip":0,"limit":2}';
            HttpResponse productsRes = new HttpResponse();
            productsRes.setStatusCode(200);
            productsRes.setBody(body);
            responses.add(productsRes);
            
            Test.setMock(HttpCalloutMock.class, new MockHttpCallout(responses));
            
            Test.startTest();
            String result = ProductService.syncProducts();
            Test.stopTest();
            
            // Assert only the valid product is inserted
            List<Product2> products = [SELECT Name FROM Product2 WHERE Name = 'Valid Product'];
            System.assertEquals(1, products.size(), 'Only valid product should be inserted');
        }
        
        // Helper methods for creating mock responses
        private static HttpResponse createLoginResponse() {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
        res.setBody('{"id":1,"username":"' + TEST_USERNAME + '","email":"emily.johnson@x.dummyjson.com","firstName":"Emily","lastName":"Johnson","gender":"female","image":"https://dummyjson.com/icon/emilys/128","accessToken":"mock-access-token","refreshToken":"mock-refresh-token"}');
        return res;
    }
    
    private static HttpResponse createProductsResponse() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('{"products":[{"id":1,"title":"API Product","description":"API Description","price":100,"discountPercentage":10,"rating":4.5,"stock":50,"brand":"API Brand","category":"API Category","thumbnail":"https://example.com/thumb.jpg","images":["https://example.com/img1.jpg"],"tags":["tag1"]}],"total":1,"skip":0,"limit":1}');
        return res;
    }
    
    private static HttpResponse createEmptyProductsResponse() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setBody('{"products":[],"total":0,"skip":0,"limit":0}');
        return res;
    }
    
    private static HttpResponse createErrorResponse() {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(401);
        res.setBody('{"message":"Invalid credentials"}');
        return res;
    }
}