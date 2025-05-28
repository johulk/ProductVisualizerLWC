@isTest
private class ProductAPIConfigServiceTest {
    // Mock class for HTTP callouts
    private class MockHttpCallout implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        private String expectedEndpoint;
        private Boolean isRefreshCall = false;
        
        public MockHttpCallout(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        
        public MockHttpCallout(Integer statusCode, String body, String expectedEndpoint) {
            this.statusCode = statusCode;
            this.body = body;
            this.expectedEndpoint = expectedEndpoint;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();            
            // If this is a refresh request, return the refresh response
            if (req.getEndpoint().endsWith('/auth/refresh')) {
                res.setStatusCode(200);
                res.setBody('{"accessToken":"mock-refreshed-token","refreshToken":"mock-new-refresh-token"}');
            } else if (req.getEndpoint().endsWith('/auth/me')) {
                // Return user details for /auth/me endpoint
                res.setStatusCode(200);
                res.setBody('{"id":1,"username":"emilys","email":"emily.johnson@x.dummyjson.com","firstName":"Emily","lastName":"Johnson","gender":"female","image":"https://dummyjson.com/icon/emilys/128"}');
            } else {
                // Otherwise return the configured response
                res.setStatusCode(statusCode);
                res.setBody(body);
            }

            return res;
        }
    }
    
    @isTest
    static void testAuthentication() {
        // Mock successful login response
        String mockLoginResponse = '{"id":1,"username":"emilys","email":"emily.johnson@x.dummyjson.com","firstName":"Emily","lastName":"Johnson","gender":"female","image":"https://dummyjson.com/icon/emilys/128","accessToken":"mock-access-token","refreshToken":"mock-refresh-token"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, mockLoginResponse));
        
        Test.startTest();
        
        // Test getting access token
        String token = ProductAPIConfigService.getAccessToken();
        System.assertNotEquals(null, token, 'Access token should not be null');
        System.assertEquals('mock-access-token', token, 'Should get mock access token');
        
        // Test token caching
        String token2 = ProductAPIConfigService.getAccessToken();
        System.assertEquals(token, token2, 'Tokens should be cached');
        
        Test.stopTest();
    }
    
    @isTest
    static void testInvalidCredentials() {
        // Mock failed login response
        String mockErrorResponse = '{"message":"Invalid credentials"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(401, mockErrorResponse));
        
        Test.startTest();
        
        try {
            ProductAPIConfigService.getAccessToken();
            System.assert(false, 'Should have thrown an exception');
        } catch(ProductAPIConfigService.ProductAPIException e) {
            System.assert(e.getMessage().contains('Failed to authenticate'), 'Should throw authentication error');
        }
        
        Test.stopTest();
    }
    
    @isTest
    static void testTokenRefresh() {
        // Mock successful initial login response
        String mockLoginResponse = '{"id":1,"username":"emilys","email":"emily.johnson@x.dummyjson.com","firstName":"Emily","lastName":"Johnson","gender":"female","image":"https://dummyjson.com/icon/emilys/128","accessToken":"mock-access-token","refreshToken":"mock-refresh-token"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, mockLoginResponse));
        
        Test.startTest();
        
        // Get initial token
        String initialToken = ProductAPIConfigService.getAccessToken();
        System.assertEquals('mock-access-token', initialToken, 'Should get initial token');
        
        // Clear only the access token to force a refresh
        ProductAPIConfigService.clearTokens();
        
        // Get new token (should trigger refresh)
        String refreshedToken = ProductAPIConfigService.getAccessToken();
        System.assertNotEquals(initialToken, refreshedToken, 'Token should be refreshed');
        System.assertEquals('mock-refreshed-token', refreshedToken, 'Should get refreshed token');
        
        Test.stopTest();
    }
    
    // List-based mock for sequential callouts (matches ProductServiceTest)
    private class ListMockHttpCallout implements HttpCalloutMock {
        private List<HttpResponse> responses;
        private Integer callCount = 0;
        public ListMockHttpCallout(List<HttpResponse> responses) {
            this.responses = responses;
        }
        public HTTPResponse respond(HTTPRequest req) {
            if (callCount < responses.size()) {
                return responses[callCount++];
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{"error":"Not Found"}');
            return res;
        }
    }

    @isTest
    static void testGetAuthenticatedUser() {
        // Success
        HttpResponse loginRes = new HttpResponse();
        loginRes.setStatusCode(200);
        loginRes.setBody('{"id":1,"username":"emilys","email":"emily.johnson@x.dummyjson.com","firstName":"Emily","lastName":"Johnson","gender":"female","image":"https://dummyjson.com/icon/emilys/128","accessToken":"mock-access-token","refreshToken":"mock-refresh-token"}');

        HttpResponse userRes = new HttpResponse();
        userRes.setStatusCode(200);
        userRes.setBody('{"id":1,"username":"emilys"}');

        List<HttpResponse> responses = new List<HttpResponse>{loginRes, userRes};
        Test.setMock(HttpCalloutMock.class, new ListMockHttpCallout(responses));
        Map<String, Object> user = ProductAPIConfigService.getAuthenticatedUser();
        System.assertEquals('emilys', user.get('username'));

        // Failure
        HttpResponse failRes = new HttpResponse();
        failRes.setStatusCode(401);
        failRes.setBody('{"error":"Unauthorized"}');
        Test.setMock(HttpCalloutMock.class, new ListMockHttpCallout(new List<HttpResponse>{failRes}));
        try {
            ProductAPIConfigService.getAuthenticatedUser();
            System.assert(false, 'Should have thrown exception');
        } catch (ProductAPIConfigService.ProductAPIException e) {
            System.assert(e.getMessage().contains('Failed to get user details'));
        }
    }
}