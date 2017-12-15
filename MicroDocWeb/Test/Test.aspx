<%@ Page Language="C#" AutoEventWireup="true" CodeBehind="Test.aspx.cs" Inherits="MicroDocWeb.Test" %>
<%@ Register TagPrefix="uc" TagName="NoteEditor" Src="~/UserCtrls/NoteEditor.ascx" %>
<!DOCTYPE html>

<html xmlns="http://www.w3.org/1999/xhtml">
<head runat="server">
    <title></title>
</head>
<body>
    <form id="form1" runat="server">
    <div>
        <asp:TextBox ID="txtSize" runat="server"></asp:TextBox>
        <asp:Button ID="btnPrint" runat="server" Text="Print" OnClick="btnPrint_Click" />
        <uc:NoteEditor ID="noteEditor" runat="server" />
    </div>
    </form>
</body>
</html>
