/** Service for API config and authentication. */
public with sharing class ProductAPIConfigService {
    // Config
    private static final String CONFIG_NAME = 'Default';
    private static String accessToken;
    private static String refreshToken;
    private static Datetime tokenExpiry;
    
    /** Get API config. */
    public static Product_API_Config__mdt getConfig() {
        Product_API_Config__mdt config = [
            SELECT API_Endpoint__c, Username__c, Password__c
            FROM Product_API_Config__mdt
            WHERE DeveloperName = :CONFIG_NAME
            LIMIT 1
        ];
        
        if (config == null) {
            throw new ProductAPIException('Product API configuration not found');
        }
        
        return config;
    }
    
    /** Get endpoint. */
    public static String getEndpoint() {
        return getConfig().API_Endpoint__c;
    }
    
    /** Get username. */
    public static String getUsername() {
        return getConfig().Username__c;
    }
    
    /** Get password. */
    public static String getPassword() {
        return getConfig().Password__c;
    }
    
    /** Get or refresh access token. */
    public static String getAccessToken() {
        if (accessToken != null && tokenExpiry != null && tokenExpiry > Datetime.now()) {
            return accessToken;
        }
        if (refreshToken != null) {
            try {
                return refreshAccessToken();
            } catch (ProductAPIException e) {}
        }
        return login();
    }
    
    /** Login for new access token. */
    private static String login() {
        Product_API_Config__mdt config = getConfig();
        HttpRequest req = new HttpRequest();
        String loginEndpoint = config.API_Endpoint__c + '/auth/login';
        req.setEndpoint(loginEndpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, String>{
            'username' => config.Username__c,
            'password' => config.Password__c
        }));
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> response = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            accessToken = (String)response.get('accessToken');
            refreshToken = (String)response.get('refreshToken');
            tokenExpiry = Datetime.now().addMinutes(30);
            return accessToken;
        } else {
            throw new ProductAPIException('Failed to authenticate: ' + res.getBody());
        }
    }
    
    /** Refresh access token. */
    private static String refreshAccessToken() {
        Product_API_Config__mdt config = getConfig();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.API_Endpoint__c + '/auth/refresh');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, String>{
            'refreshToken' => refreshToken
        }));
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> response = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            accessToken = (String)response.get('accessToken');
            refreshToken = (String)response.get('refreshToken');
            tokenExpiry = Datetime.now().addHours(1);
            return accessToken;
        } else {
            throw new ProductAPIException('Failed to refresh token: ' + res.getBody());
        }
    }
    
    /** API error. */
    public class ProductAPIException extends Exception {}
    
    /** Get authenticated user from API. */
    public static Map<String, Object> getAuthenticatedUser() {
        Product_API_Config__mdt config = getConfig();
        String token = getAccessToken();
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(config.API_Endpoint__c + '/auth/me');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            return (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
        } else {
            throw new ProductAPIException('Failed to get user details: ' + res.getBody());
        }
    }
    
    /** Clear tokens (for tests). */
    public static void clearTokens() {
        accessToken = null;
        tokenExpiry = null;
    }
    
    /** Add auth header to request. */
    public static void addAuthHeader(HttpRequest request) {
        String token = getAccessToken();
        if (token != null) {
            request.setHeader('Authorization', 'Bearer ' + token);
        }
    }
}