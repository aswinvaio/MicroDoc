<%@ Page Title="" Language="C#" MasterPageFile="~/MasterPages/MicrodocMaster.Master" AutoEventWireup="true" CodeBehind="Test2.aspx.cs" Inherits="MicroDocWeb.Test2" %>

<%@ Register TagPrefix="uc" TagName="NoteEditor" Src="~/UserCtrls/NoteEditor.ascx" %>

<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <uc:NoteEditor ID="noteEditor" runat="server" />
</asp:Content>
