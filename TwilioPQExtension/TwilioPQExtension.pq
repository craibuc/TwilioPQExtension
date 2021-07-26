section Twilio;

[DataSource.Kind="Twilio", Publish="Twilio.Publish"]
shared Twilio.Contents = (optional message as text) =>
    let
        //data = Messages()
        data = NavigationTable()
    in
        data
;

// Data Source Kind description
Twilio = [
    Authentication = [
        UsernamePassword = [
            UsernameLabel=Extension.LoadString("UsernameLabel"),
            PasswordLabel=Extension.LoadString("PasswordLabel")
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
Twilio.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/craibuc/TwilioPQExtension",
    SourceImage = Twilio.Icons,
    SourceTypeImage = Twilio.Icons
];

Twilio.Icons = [
    Icon16 = { Extension.Contents("Twilio16.png"), Extension.Contents("Twilio20.png"), Extension.Contents("Twilio24.png"), Extension.Contents("Twilio32.png") },
    Icon32 = { Extension.Contents("Twilio32.png"), Extension.Contents("Twilio40.png"), Extension.Contents("Twilio48.png"), Extension.Contents("Twilio64.png") }
];

/*
Purpose:
    Return tables and other objects that will be visible in Power BI's Navigation dialog
Parameters:
    subdomain - the name of the customer's subdomain (e.g. https://[subdomain].bamboohr.com/)
*/
shared NavigationTable = () =>
    let
        objects = #table(
            {"Name","Key","Data","ItemKind", "ItemName","IsLeaf"},
            {
                {"Messages", "messagges", Messages(), "Table", "Table", true}
            }),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable
;

/*
Purpose: create HTTP Basic authentication token
*/
BasicAuth = 
let
    Source = Extension.CurrentCredential()[Username] & ":" & Extension.CurrentCredential()[Password],
    Bytes = Text.ToBinary(Source),
    TextForm = Text.Combine({"Basic", Binary.ToText(Bytes, BinaryEncoding.Base64)}, " ")
in
    TextForm
;

/*
Purpose:
    Compose the initial relative path in the form of /2010-04-01/Accounts/SID/Messages.json
Parameters:
    The resource to retrieve (e.g. Messages.json)
*/
InitialRelativePath = (resource as text) =>
    let
        AccountSid = Extension.CurrentCredential()[Username],
        RelativePath = Text.Combine({"/2010-04-01/Accounts", AccountSid, resource}, "/")
    in
        RelativePath
;

/*
Purpose:
    Retrieve table of Twilio SMS messages
Parameters:

Links:
    https://www.twilio.com/docs/sms/api/message-resource#fetch-a-message-resource
*/

Messages = () =>
    let
        RelativePath = InitialRelativePath("Messages.json"),
        data = GetAllPagesByNextLink(RelativePath, "messages")
    in
        data
;

/*
Purpose: retrieve all pages of data; will continue to request data until the next page link is null.
Parameters:
    uri - API endpoint
*/

GetAllPagesByNextLink = (RelativePath as text, Field as text) as table =>
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            nextLink = if (previous = null) then RelativePath else Value.Metadata(previous)[NextLink]?,
            // if NextLink was set to null by the previous call, we know we have no more data
            page = if (nextLink <> null) then GetPage(nextLink, Field) else null
        in
            page
    )
;

/*
*/
GetPage = (RelativePath as text, Node as text) as any =>
    let
        BaseUri = "https://api.twilio.com",
        DefaultRequestHeaders = [
            #"Authorization"=BasicAuth
        ],
        response = Web.Contents(BaseUri, [ Headers = DefaultRequestHeaders, RelativePath = RelativePath]),
        body = Json.Document(response),
        nextLink = GetNextLink(body),
        nodes = Record.FieldOrDefault(body,Node),
        data = Table.FromRecords(nodes)

    in
        data meta [NextLink = nextLink]
;

/*
Purpose:
  Parse the JSON response and return the value of the "next_page_urL" (or null if it doesn't exist)
Notes:
  "/2010-04-01/Accounts/{AccountSid}/Messages.json?PageSize=50&Page=1&PageToken=PASMebd30acbee8f2257ff534fe5772d837d",
*/
GetNextLink = (response) as nullable text => 
    Record.FieldOrDefault(response, "next_page_uri")
;

/*
The getNextPage function takes a single argument and is expected to return a nullable table
*/

Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        // concatenate the pages together
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            )
;

/*
Purpose:
    Create a navigation table 
*/
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable
;
